import Foundation
import SwiftData

/// The SwiftData-backed ``Database``, and the one thing allowed to decide whether a store mirrors to
/// CloudKit.
///
/// An actor because its container is replaceable: a `ModelConfiguration` cannot change once its
/// container exists, so turning sync on or off at runtime means building a new container against
/// the same file.
public final actor DatabaseDefault: Database {
    public nonisolated let configuration: DatabaseConfiguration
    public nonisolated let isEphemeral: Bool
    public private(set) var isCloudKitEnabled: Bool

    private var modelContainer: ModelContainer?
    private var cachedModelActor: DatabaseActor?
    private nonisolated let logger: any DatabaseLogger

    public init(
        configuration: DatabaseConfiguration,
        logger: any DatabaseLogger = DatabaseLoggerDefault()
    ) throws {
        let cloudKitEnabled = configuration.cloudKit?.isEnabledAtLaunch == true
            && configuration.canMirror
            && !ProcessEnvironment.isRunningTests
        let container = try ModelContainerFactory.makeContainer(
            for: configuration,
            cloudKitEnabled: cloudKitEnabled,
            logger: logger
        )

        self.configuration = configuration
        self.modelContainer = container
        self.isEphemeral = configuration.location == .inMemory
        self.isCloudKitEnabled = cloudKitEnabled
        self.logger = logger
        logger.log(
            .info,
            "Database \(configuration.name) opened at \(container.configurations.first?.url.path ?? "memory"), CloudKit mirroring \(cloudKitEnabled ? "on" : "off")"
        )
    }

    private init(configuration: DatabaseConfiguration, modelContainer: ModelContainer?, logger: any DatabaseLogger) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.isEphemeral = true
        self.isCloudKitEnabled = false
        self.logger = logger
    }

    /// The file this process opened. Worth logging once at launch: `.main` resolves to a different
    /// file in every process, `.group` to the same one.
    public nonisolated var storeURL: URL {
        ModelContainerFactory.makeModelConfiguration(for: configuration, cloudKitEnabled: false).url
    }

    /// Cached so the store stays one actor; rebuilt lazily after a container swap.
    public func modelActor() throws -> DatabaseActor {
        if let cachedModelActor {
            return cachedModelActor
        }
        guard let modelContainer else {
            throw DatabaseError.storageUnavailable
        }

        let actor = DatabaseActor(modelContainer: modelContainer, logger: logger)
        cachedModelActor = actor

        return actor
    }

    /// Two things this deliberately does not promise:
    ///
    /// - Callers reach the store in two hops (`modelActor()`, then the operation), so a call already
    ///   past the first hop lands on the outgoing actor. Both write the same file, so a saved row is
    ///   safe; the flush before the swap covers an unsaved one.
    /// - Releasing the outgoing container does not recall mirroring work the system already
    ///   scheduled. Turning sync off stops new exports, not the ones in flight.
    public func setCloudKitEnabled(_ enabled: Bool) async throws {
        guard configuration.canMirror, !isEphemeral, !ProcessEnvironment.isRunningTests else {
            logger.log(.debug, "Database \(configuration.name): ignoring setCloudKitEnabled(\(enabled)) — this store never mirrors")
            return
        }
        guard enabled != isCloudKitEnabled else { return }

        try await swapContainer(cloudKitEnabled: enabled)
        isCloudKitEnabled = enabled
        logger.log(.info, "Database \(configuration.name): rebuilt with CloudKit mirroring \(enabled ? "on" : "off")")
    }

    /// The swap machinery of ``setCloudKitEnabled(_:)`` with the CloudKit decision taken out, so tests
    /// can cover the part that can lose data without touching CloudKit.
    package func rebuildContainer() async throws {
        try await swapContainer(cloudKitEnabled: isCloudKitEnabled)
    }

    private func swapContainer(cloudKitEnabled: Bool) async throws {
        guard configuration.canRebuild, !isEphemeral else { return }

        // Built first: a throw here leaves the live container untouched.
        let replacement = try ModelContainerFactory.makeContainer(
            for: configuration,
            cloudKitEnabled: cloudKitEnabled,
            logger: logger
        )

        try? await cachedModelActor?.save()
        cachedModelActor = nil
        modelContainer = replacement
    }
}

extension DatabaseDefault {
    /// A store held only in memory, for when the real one cannot be opened.
    ///
    /// **Cannot fail** — that is its whole job. In the one case where `ModelContainer` still refuses,
    /// the store constructs with nothing behind it and every operation throws
    /// ``DatabaseError/storageUnavailable``. A degraded session either way, never a trap.
    public static func ephemeral(
        schema: any DatabaseSchema.Type,
        logger: any DatabaseLogger = DatabaseLoggerDefault()
    ) -> DatabaseDefault {
        let container: ModelContainer?
        do {
            container = try ModelContainerFactory.makeEphemeralContainer(for: schema)
        } catch {
            logger.log(.error, "Ephemeral database unavailable: \(error)")
            container = nil
        }

        return DatabaseDefault(
            configuration: DatabaseConfiguration(name: "ephemeral", schema: schema, location: .inMemory),
            modelContainer: container,
            logger: logger
        )
    }

    /// The real store, degrading to ``ephemeral(schema:logger:)`` when it cannot be opened.
    ///
    /// A corrupt file or a migration that throws would otherwise be a `fatalError` at launch — no
    /// diagnostics, and no way back in for the user short of deleting the app. This starts, reports
    /// through ``isEphemeral`` that it is not saving, and stays usable.
    ///
    /// - Parameter onFailure: Called with the error before degrading, for logging or crash reporting.
    public static func makeOrEphemeral(
        configuration: DatabaseConfiguration,
        logger: any DatabaseLogger = DatabaseLoggerDefault(),
        onFailure: (any Error) -> Void = { _ in }
    ) -> DatabaseDefault {
        do {
            return try DatabaseDefault(configuration: configuration, logger: logger)
        } catch {
            logger.log(.error, "Database \(configuration.name) failed to open, degrading to memory: \(error)")
            onFailure(error)

            return ephemeral(schema: configuration.schema, logger: logger)
        }
    }
}

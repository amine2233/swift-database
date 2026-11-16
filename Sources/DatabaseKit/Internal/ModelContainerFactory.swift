import CoreData
import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Core Data's codes for "this file's model version is not one the plan knows".
    private static let incompatibleStoreCodes: Set<Int> = [
        NSPersistentStoreIncompatibleVersionHashError,
        NSMigrationError,
        NSMigrationMissingSourceModelError,
        NSMigrationMissingMappingModelError,
        134_504
    ]

    static func makeContainer(
        for configuration: DatabaseConfiguration,
        cloudKitEnabled: Bool,
        logger: any DatabaseLogger
    ) throws -> ModelContainer {
        let modelConfiguration = makeModelConfiguration(for: configuration, cloudKitEnabled: cloudKitEnabled)

        do {
            return try makeContainer(configuration.schema, modelConfiguration)
        } catch where configuration.incompatibleStorePolicy == .deleteAndRecreate && isIncompatibleStore(error) {
            logger.log(.error, "Database \(configuration.name): incompatible store deleted and recreated — \(error)")
            removeStore(at: modelConfiguration.url)

            return try makeContainer(configuration.schema, modelConfiguration)
        }
    }

    static func makeEphemeralContainer(for schema: any DatabaseSchema.Type) throws -> ModelContainer {
        try ModelContainer(
            for: schema.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    static func makeModelConfiguration(
        for configuration: DatabaseConfiguration,
        cloudKitEnabled: Bool
    ) -> ModelConfiguration {
        let schema = configuration.schema.schema
        let cloudKitDatabase = cloudKitEnabled ? configuration.cloudKit?.database ?? .none : .none

        return switch configuration.location {
        case .main:
            ModelConfiguration(
                configuration.name,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: configuration.allowsSave,
                groupContainer: .none,
                cloudKitDatabase: cloudKitDatabase
            )
        case let .group(identifier):
            ModelConfiguration(
                configuration.name,
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: configuration.allowsSave,
                groupContainer: .identifier(identifier),
                cloudKitDatabase: cloudKitDatabase
            )
        case let .url(url):
            ModelConfiguration(
                configuration.name,
                schema: schema,
                url: url,
                allowsSave: configuration.allowsSave,
                cloudKitDatabase: .none
            )
        case .inMemory:
            ModelConfiguration(
                configuration.name,
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: configuration.allowsSave,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
    }

    private static func makeContainer(
        _ schema: any DatabaseSchema.Type,
        _ modelConfiguration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema.schema,
            migrationPlan: schema.migrationPlan,
            configurations: [modelConfiguration]
        )
    }

    /// Only a schema mismatch qualifies. A store that is merely unreadable right now — file protection
    /// while the device is locked, which an extension woken in the background hits — must never be
    /// deleted.
    static func isIncompatibleStore(_ error: any Error) -> Bool {
        underlyingErrors(of: error).contains { error in
            error.domain == NSCocoaErrorDomain && incompatibleStoreCodes.contains(error.code)
        }
    }

    /// `SwiftDataError` bridges to an `NSError` with an empty `userInfo`, so the Core Data error that
    /// says *why* the container failed is reachable only through reflection.
    private static func underlyingErrors(of error: any Error) -> [NSError] {
        let nsError = error as NSError
        let wrapped = Mirror(reflecting: error).children.compactMap { child -> (any Error)? in
            if let error = child.value as? any Error {
                return error
            }
            return Mirror(reflecting: child.value).children.first?.value as? any Error
        }
        let chained = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { [$0] } ?? []

        return [nsError] + (wrapped + chained)
            .filter { ($0 as NSError) !== nsError }
            .flatMap(underlyingErrors(of:))
    }

    /// The SQLite file and its write-ahead log: deleting only the first leaves the other two to be
    /// replayed into the fresh store.
    private static func removeStore(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}

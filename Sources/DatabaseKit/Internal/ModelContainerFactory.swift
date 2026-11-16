import CoreData
import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeContainer(
        for configuration: DatabaseConfiguration,
        cloudKitEnabled: Bool,
        logger: any DatabaseLogger
    ) throws -> ModelContainer {
        let modelConfiguration = makeModelConfiguration(for: configuration, cloudKitEnabled: cloudKitEnabled)

        do {
            return try makeContainer(configuration.schema, modelConfiguration)
        } catch where configuration.incompatibleStorePolicy == .deleteAndRecreate
            && storeMatchesNoKnownVersion(at: modelConfiguration.url, schema: configuration.schema) {
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

    /// Whether the file on disk was written by a model version no stage of the plan knows.
    ///
    /// Decided from the store's own metadata rather than from the error: `SwiftDataError` hides the
    /// Core Data cause, and its layout differs between OS releases. A store whose metadata cannot be
    /// read right now — file protection while the device is locked, which an extension woken in the
    /// background hits — is never treated as incompatible, so it is never deleted.
    static func storeMatchesNoKnownVersion(at url: URL, schema: any DatabaseSchema.Type) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url) else {
            return false
        }

        let knownVersions = schema.migrationPlan?.schemas.map { $0.models } ?? [schema.models]
        // A version whose model cannot be built is assumed to match: unsure means keep the file.
        return !knownVersions.contains { models in
            NSManagedObjectModel.makeManagedObjectModel(for: models)?
                .isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) ?? true
        }
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

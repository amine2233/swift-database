@testable import DatabaseKit
import Foundation
import SwiftData
import Testing

@Suite("Migration")
struct MigrationTests {
    @Test func aFirstReleaseStoreMigratesAndKeepsItsRows() async throws {
        let directory = try TemporaryDirectory()
        let id = UUID()
        try await seedFirstReleaseStore(at: directory.storeURL(), id: id, title: "From V1")

        let database = try DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
        let migrated = try await database.repository(for: NoteEntity.self).fetch(id: id)

        #expect(migrated?.title == "From V1")
        #expect(migrated?.body == "")
    }

    @Test func anUnknownVersionFailsByDefault() async throws {
        let directory = try TemporaryDirectory()
        try await seedCurrentStore(at: directory.storeURL())

        #expect(throws: (any Error).self) {
            try DatabaseDefault(
                configuration: .notes(at: directory.storeURL(), schema: NoteSchemaIncompatible.self),
                logger: DatabaseLoggerMock()
            )
        }
    }

    @Test func anUnknownVersionIsRecreatedWhenAllowed() async throws {
        let directory = try TemporaryDirectory()
        try await seedCurrentStore(at: directory.storeURL())
        var configuration = DatabaseConfiguration.notes(at: directory.storeURL(), schema: NoteSchemaIncompatible.self)
        configuration.incompatibleStorePolicy = .deleteAndRecreate

        let database = try DatabaseDefault(configuration: configuration, logger: DatabaseLoggerMock())
        let count = try await database.modelActor().perform { context in
            try context.fetchCount(FetchDescriptor<NoteSchemaIncompatible.V1.NoteEntity>())
        }

        #expect(count == 0)
    }

    private func seedFirstReleaseStore(at url: URL, id: UUID, title: String) async throws {
        let database = try DatabaseDefault(
            configuration: .notes(at: url, schema: NoteSchemaFirstRelease.self),
            logger: DatabaseLoggerMock()
        )
        try await database.modelActor().perform { context in
            context.insert(NoteSchemaV1.NoteEntity(id: id, title: title, createdAt: .now))
            try context.save()
        }
    }

    private func seedCurrentStore(at url: URL) async throws {
        let database = try DatabaseDefault(configuration: .notes(at: url), logger: DatabaseLoggerMock())
        try await database.repository(for: NoteEntity.self).upsert(Note(title: "From V2"))
    }
}

@Suite("Incompatible store detection")
struct IncompatibleStoreDetectionTests {
    @Test func aStoreFromAKnownVersionIsCompatible() async throws {
        let directory = try TemporaryDirectory()
        try await DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
            .repository(for: NoteEntity.self)
            .upsert(Note(title: "Known"))

        #expect(!ModelContainerFactory.storeMatchesNoKnownVersion(at: directory.storeURL(), schema: NoteSchema.self))
    }

    @Test func aStoreFromAnUnknownVersionIsIncompatible() async throws {
        let directory = try TemporaryDirectory()
        try await DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
            .repository(for: NoteEntity.self)
            .upsert(Note(title: "Unknown to the old plan"))

        #expect(ModelContainerFactory.storeMatchesNoKnownVersion(
            at: directory.storeURL(),
            schema: NoteSchemaIncompatible.self
        ))
    }

    @Test func aMissingOrUnreadableFileIsNeverIncompatible() throws {
        let directory = try TemporaryDirectory()

        #expect(!ModelContainerFactory.storeMatchesNoKnownVersion(at: directory.storeURL(), schema: NoteSchema.self))
    }
}

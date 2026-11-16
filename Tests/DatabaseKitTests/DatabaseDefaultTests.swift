@testable import DatabaseKit
import Foundation
import SwiftData
import Testing

@Suite("DatabaseDefault")
struct DatabaseDefaultTests {
    @Test func aFileStorePersistsAcrossInstances() async throws {
        let directory = try TemporaryDirectory()
        let note = Note(title: "Persisted")

        do {
            let database = try DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
            try await database.repository(for: NoteEntity.self).upsert(note)
        }

        let reopened = try DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
        #expect(try await reopened.repository(for: NoteEntity.self).fetchAll() == [note])
        #expect(reopened.isEphemeral == false)
    }

    @Test func rebuildKeepsSavedRows() async throws {
        let directory = try TemporaryDirectory()
        let database = try DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
        let repository = database.repository(for: NoteEntity.self)
        let note = Note(title: "Survives")
        try await repository.upsert(note)
        let actorBefore = try await database.modelActor()

        try await database.rebuildContainer()

        #expect(try await database.modelActor() !== actorBefore)
        #expect(try await repository.fetchAll() == [note])
    }

    @Test func rebuildFlushesUnsavedChanges() async throws {
        let directory = try TemporaryDirectory()
        let database = try DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
        let id = UUID()
        try await database.modelActor().perform { context in
            context.insert(NoteEntity(id: id, title: "Unsaved", body: "", createdAt: .now))
        }

        try await database.rebuildContainer()

        #expect(try await database.repository(for: NoteEntity.self).fetch(id: id)?.title == "Unsaved")
    }

    @Test func rebuildIsANoOpForAnInMemoryStore() async throws {
        let database = try DatabaseDefault(configuration: .inMemoryNotes(), logger: DatabaseLoggerMock())
        try await database.repository(for: NoteEntity.self).upsert(Note(title: "Kept"))

        try await database.rebuildContainer()

        #expect(try await database.repository(for: NoteEntity.self).count() == 1)
    }

    @Test func cloudKitIsNeverEnabledInsideATestHost() async throws {
        let configuration = DatabaseConfiguration(
            name: "Notes",
            schema: NoteSchema.self,
            location: .inMemory,
            cloudKit: CloudKitSync(isEnabledAtLaunch: true)
        )
        let database = try DatabaseDefault(configuration: configuration, logger: DatabaseLoggerMock())

        try await database.setCloudKitEnabled(true)

        #expect(await database.isCloudKitEnabled == false)
    }

    @Test func ephemeralIsUsableAndSaysSo() async throws {
        let database = DatabaseDefault.ephemeral(schema: NoteSchema.self, logger: DatabaseLoggerMock())

        try await database.repository(for: NoteEntity.self).upsert(Note(title: "Volatile"))

        #expect(database.isEphemeral)
        #expect(try await database.repository(for: NoteEntity.self).count() == 1)
    }

    @Test func makeOrEphemeralDegradesWhenTheStoreCannotOpen() async throws {
        let directory = try TemporaryDirectory()
        let blocker = directory.url.appending(path: "not-a-directory")
        try Data().write(to: blocker)
        var reported: (any Error)?

        let database = DatabaseDefault.makeOrEphemeral(
            configuration: .notes(at: blocker.appending(path: "Notes.store")),
            logger: DatabaseLoggerMock(),
            onFailure: { reported = $0 }
        )

        #expect(reported != nil)
        #expect(database.isEphemeral)
        #expect(try await database.repository(for: NoteEntity.self).count() == 0)
    }

    @Test func makeOrEphemeralReturnsTheRealStoreWhenItOpens() throws {
        let directory = try TemporaryDirectory()
        var reported: (any Error)?

        let database = DatabaseDefault.makeOrEphemeral(
            configuration: .notes(at: directory.storeURL()),
            logger: DatabaseLoggerMock(),
            onFailure: { reported = $0 }
        )

        #expect(reported == nil)
        #expect(database.isEphemeral == false)
    }

    @Test func writesAreLogged() async throws {
        let logger = DatabaseLoggerMock()
        let database = try DatabaseDefault(configuration: .inMemoryNotes(), logger: logger)

        try await database.repository(for: NoteEntity.self).upsert(Note(title: "Logged"))

        #expect(logger.messages.contains { $0.0 == .info && $0.1.contains("upserted 1 NoteEntity") })
    }
}

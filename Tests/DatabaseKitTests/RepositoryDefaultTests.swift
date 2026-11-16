@testable import DatabaseKit
import Foundation
import SwiftData
import Testing

@Suite("RepositoryDefault")
struct RepositoryDefaultTests {
    let database: DatabaseDefault
    let repository: RepositoryDefault<NoteEntity>

    init() throws {
        database = try DatabaseDefault(configuration: .inMemoryNotes(), logger: DatabaseLoggerMock())
        repository = database.repository(for: NoteEntity.self)
    }

    @Test func upsertInsertsNewModels() async throws {
        let notes = [Note(title: "A"), Note(title: "B")]

        try await repository.upsert(notes)

        #expect(try await repository.count() == 2)
        #expect(Set(try await repository.fetchAll().map(\.id)) == Set(notes.map(\.id)))
    }

    @Test func upsertUpdatesTheRowCarryingTheSameID() async throws {
        let note = Note(title: "Draft")
        try await repository.upsert(note)

        var edited = note
        edited.title = "Final"
        try await repository.upsert(edited)

        #expect(try await repository.count() == 1)
        #expect(try await repository.fetch(id: note.id) == edited)
    }

    @Test func upsertCollapsesDuplicateIDsWithinOneBatch() async throws {
        let id = UUID()

        try await repository.upsert([Note(id: id, title: "First"), Note(id: id, title: "Second")])

        #expect(try await repository.count() == 1)
        #expect(try await repository.fetch(id: id)?.title == "Second")
    }

    @Test func updateOverwritesAnExistingRow() async throws {
        let note = Note(title: "Before")
        try await repository.upsert(note)

        var edited = note
        edited.body = "After"
        try await repository.update(edited)

        #expect(try await repository.fetch(id: note.id)?.body == "After")
    }

    @Test func updateRefusesToCreateARow() async throws {
        await #expect(throws: DatabaseError.notFound(entity: "NoteEntity")) {
            try await repository.update(Note(title: "Ghost"))
        }
        #expect(try await repository.count() == 0)
    }

    @Test func fetchReturnsNilForAnUnknownID() async throws {
        #expect(try await repository.fetch(id: UUID()) == nil)
    }

    @Test func deleteRemovesOnlyTheGivenIDs() async throws {
        let keep = Note(title: "Keep")
        let drop = Note(title: "Drop")
        try await repository.upsert([keep, drop])

        try await repository.delete(id: drop.id)

        #expect(try await repository.fetchAll() == [keep])
    }

    @Test func deleteAllEmptiesTheStore() async throws {
        try await repository.upsert([Note(title: "A"), Note(title: "B")])

        try await repository.deleteAll()

        #expect(try await repository.count() == 0)
    }

    @Test func applyUpsertsAndDeletesInOneBatch() async throws {
        let existing = Note(title: "Existing")
        let removed = Note(title: "Removed")
        try await repository.upsert([existing, removed])

        var edited = existing
        edited.title = "Edited"
        let added = Note(title: "Added")
        try await repository.apply(DatabaseChangeSet(upserts: [edited, added], deletions: [removed.id]))

        let titles = try await repository.fetchAll().map(\.title).sorted()
        #expect(titles == ["Added", "Edited"])
    }

    @Test func fetchHonoursPredicateSortAndLimit() async throws {
        try await repository.upsert([
            Note(title: "b", createdAt: Date(timeIntervalSince1970: 2)),
            Note(title: "a", createdAt: Date(timeIntervalSince1970: 1)),
            Note(title: "skip", createdAt: Date(timeIntervalSince1970: 3)),
        ])

        var descriptor = FetchDescriptor<NoteEntity>(
            predicate: #Predicate { $0.title != "skip" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 2

        #expect(try await repository.fetch(descriptor).map(\.title) == ["a", "b"])
        #expect(try await repository.count(FetchDescriptor<NoteEntity>(predicate: #Predicate { $0.title == "skip" })) == 1)
    }

    @Test func emptyWritesAreNoOps() async throws {
        try await repository.upsert([])
        try await repository.delete(ids: [])
        try await repository.apply(DatabaseChangeSet())

        #expect(try await repository.count() == 0)
    }

    @Test func aFailedWriteIsRolledBack() async throws {
        let directory = try TemporaryDirectory()
        try await DatabaseDefault(configuration: .notes(at: directory.storeURL()), logger: DatabaseLoggerMock())
            .repository(for: NoteEntity.self)
            .upsert(Note(title: "Seed"))
        var configuration = DatabaseConfiguration.notes(at: directory.storeURL())
        configuration.allowsSave = false
        let repository = try DatabaseDefault(configuration: configuration, logger: DatabaseLoggerMock())
            .repository(for: NoteEntity.self)

        await #expect(throws: (any Error).self) {
            try await repository.upsert(Note(title: "Rejected"))
        }

        // Without the rollback the unsaved insert would still be visible to the next fetch.
        #expect(try await repository.fetchAll().map(\.title) == ["Seed"])
    }
}

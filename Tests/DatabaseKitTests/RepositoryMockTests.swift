import DatabaseKit
import DatabaseKitTesting
import Testing

@Suite("RepositoryMock")
struct RepositoryMockTests {
    struct Failure: Error {}

    @Test func behavesLikeTheRealRepository() async throws {
        let mock = RepositoryMock<Note>()
        let note = Note(title: "A")

        try await mock.upsert(note)
        var edited = note
        edited.title = "B"
        try await mock.upsert(edited)

        #expect(try await mock.fetchAll() == [edited])
        await #expect(throws: DatabaseError.notFound(entity: "Note")) {
            try await mock.update(Note(title: "Ghost"))
        }
    }

    @Test func failsOnlyTheNextCall() async throws {
        let mock = RepositoryMock<Note>(models: [Note(title: "Seed")])
        await mock.failNextCall(with: Failure())

        await #expect(throws: Failure.self) { try await mock.fetchAll() }
        #expect(try await mock.count() == 1)
        #expect(await mock.calls.count == 2)
    }

    @Test func isUsableThroughTheProtocol() async throws {
        let repository: any Repository<Note> = RepositoryMock<Note>()

        try await repository.apply(DatabaseChangeSet(upserts: [Note(title: "A")]))

        #expect(try await repository.count() == 1)
    }
}

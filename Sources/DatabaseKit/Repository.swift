/// Typed, `Sendable` access to one kind of model — what features depend on, and what tests replace
/// with `RepositoryMock` from `DatabaseKitTesting`.
public protocol Repository<Model>: Sendable {
    associatedtype Model: Identifiable & Sendable where Model.ID: Sendable

    func fetchAll() async throws -> [Model]
    func fetch(id: Model.ID) async throws -> Model?
    func count() async throws -> Int

    /// Inserts each model, or updates the row already carrying its id.
    func upsert(_ models: [Model]) async throws
    /// Throws ``DatabaseError/notFound(entity:)`` rather than inserting.
    func update(_ model: Model) async throws
    func delete(ids: [Model.ID]) async throws
    func deleteAll() async throws
    /// Upserts and deletions in one save.
    func apply(_ changes: DatabaseChangeSet<Model>) async throws
}

extension Repository {
    /// Inserts `model`, or updates the row already carrying its id.
    public func upsert(_ model: Model) async throws {
        try await upsert([model])
    }

    /// Deletes the row carrying `id`; does nothing if there is none.
    public func delete(id: Model.ID) async throws {
        try await delete(ids: [id])
    }
}

public struct DatabaseChangeSet<Model: Identifiable & Sendable>: Sendable where Model.ID: Sendable {
    public var upserts: [Model]
    public var deletions: [Model.ID]

    public init(upserts: [Model] = [], deletions: [Model.ID] = []) {
        self.upserts = upserts
        self.deletions = deletions
    }

    public var isEmpty: Bool {
        upserts.isEmpty && deletions.isEmpty
    }
}

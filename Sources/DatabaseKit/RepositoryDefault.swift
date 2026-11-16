import SwiftData

/// A ``Repository`` over one ``DatabaseEntity``.
///
/// Holds the ``Database``, not its actor, and resolves the actor on every call — so a container
/// rebuilt underneath it is picked up without the repository being recreated.
public struct RepositoryDefault<Entity: DatabaseEntity>: Repository {
    public typealias Model = Entity.Model

    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    public func fetchAll() async throws -> [Model] {
        try await fetch(FetchDescriptor<Entity>())
    }

    /// Filtered, sorted or paged reads. Not on ``Repository`` because predicates and sort
    /// descriptors are written against the entity, which a mock does not have.
    public func fetch(_ descriptor: FetchDescriptor<Entity>) async throws -> [Model] {
        try await database.modelActor().fetch(descriptor)
    }

    public func fetch(id: Model.ID) async throws -> Model? {
        try await database.modelActor().fetch(Entity.self, id: id)
    }

    public func count() async throws -> Int {
        try await count(FetchDescriptor<Entity>())
    }

    public func count(_ descriptor: FetchDescriptor<Entity>) async throws -> Int {
        try await database.modelActor().count(descriptor)
    }

    public func upsert(_ models: [Model]) async throws {
        try await database.modelActor().upsert(models, as: Entity.self)
    }

    public func update(_ model: Model) async throws {
        try await database.modelActor().update(model, as: Entity.self)
    }

    public func delete(ids: [Model.ID]) async throws {
        try await database.modelActor().delete(Entity.self, ids: ids)
    }

    public func deleteAll() async throws {
        try await database.modelActor().deleteAll(Entity.self)
    }

    public func apply(_ changes: DatabaseChangeSet<Model>) async throws {
        try await database.modelActor().apply(changes, to: Entity.self)
    }
}

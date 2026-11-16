import DatabaseKit

/// An in-memory ``Repository`` for feature tests: behaves like the real one, records every call,
/// and fails on demand.
public final actor RepositoryMock<Model: Identifiable & Sendable>: Repository where Model.ID: Sendable {
    public enum Call: Sendable {
        case fetchAll
        case fetch(id: Model.ID)
        case count
        case upsert([Model])
        case update(Model)
        case delete(ids: [Model.ID])
        case deleteAll
        case apply(DatabaseChangeSet<Model>)
    }

    public private(set) var models: [Model]
    public private(set) var calls: [Call] = []

    /// Thrown by the next call instead of running it, then cleared.
    public var nextError: (any Error)?

    public init(models: [Model] = []) {
        self.models = models
    }

    public func failNextCall(with error: any Error) {
        nextError = error
    }

    public func fetchAll() throws -> [Model] {
        try record(.fetchAll)
        return models
    }

    public func fetch(id: Model.ID) throws -> Model? {
        try record(.fetch(id: id))
        return models.first { $0.id == id }
    }

    public func count() throws -> Int {
        try record(.count)
        return models.count
    }

    public func upsert(_ models: [Model]) throws {
        try record(.upsert(models))
        applyUpserts(models)
    }

    public func update(_ model: Model) throws {
        try record(.update(model))
        guard let index = models.firstIndex(where: { $0.id == model.id }) else {
            throw DatabaseError.notFound(entity: String(describing: Model.self))
        }

        models[index] = model
    }

    public func delete(ids: [Model.ID]) throws {
        try record(.delete(ids: ids))
        models.removeAll { ids.contains($0.id) }
    }

    public func deleteAll() throws {
        try record(.deleteAll)
        models.removeAll()
    }

    public func apply(_ changes: DatabaseChangeSet<Model>) throws {
        try record(.apply(changes))
        applyUpserts(changes.upserts)
        models.removeAll { changes.deletions.contains($0.id) }
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func applyUpserts(_ upserts: [Model]) {
        for model in upserts {
            if let index = models.firstIndex(where: { $0.id == model.id }) {
                models[index] = model
            } else {
                models.append(model)
            }
        }
    }
}

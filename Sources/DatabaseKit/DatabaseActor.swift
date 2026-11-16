import Foundation
import SwiftData

/// The one place a `ModelContext` is touched.
///
/// Every read maps entities to their `Sendable` ``DatabaseEntity/Model`` before returning, and every
/// write saves before returning, so no managed object and no unsaved change ever escapes the actor.
/// Autosave is off: a failed save rolls the context back instead of leaving a half-applied change
/// waiting to poison the next one.
public final actor DatabaseActor: SwiftData.ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private nonisolated let logger: any DatabaseLogger

    init(modelContainer: ModelContainer, logger: any DatabaseLogger) {
        let modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.logger = logger
    }

    // MARK: - Reads

    public func fetch<Entity: DatabaseEntity>(
        _ descriptor: FetchDescriptor<Entity> = FetchDescriptor<Entity>()
    ) throws -> [Entity.Model] {
        let entities = try modelContext.fetch(descriptor)
        logger.log(.debug, "Database read: fetched \(entities.count) \(Entity.self)")

        return entities.map { $0.makeModel() }
    }

    public func fetch<Entity: DatabaseEntity>(_: Entity.Type, id: Entity.Model.ID) throws -> Entity.Model? {
        try entity(Entity.self, id: id)?.makeModel()
    }

    public func count<Entity: DatabaseEntity>(
        _ descriptor: FetchDescriptor<Entity> = FetchDescriptor<Entity>()
    ) throws -> Int {
        try modelContext.fetchCount(descriptor)
    }

    // MARK: - Writes

    /// Inserts each model, or updates the row already carrying its id.
    public func upsert<Entity: DatabaseEntity>(_ models: [Entity.Model], as _: Entity.Type) throws {
        guard !models.isEmpty else { return }

        try write {
            try applyUpserts(models, as: Entity.self)
        }
        logger.log(.info, "Database write: upserted \(models.count) \(Entity.self)")
    }

    /// Unlike ``upsert(_:as:)``, refuses to create a row: an edit to something another device deleted
    /// must not resurrect it.
    public func update<Entity: DatabaseEntity>(_ model: Entity.Model, as _: Entity.Type) throws {
        try write {
            guard let existing = try entity(Entity.self, id: model.id) else {
                throw DatabaseError.notFound(entity: String(describing: Entity.self))
            }

            existing.update(with: model)
        }
        logger.log(.info, "Database write: updated one \(Entity.self)")
    }

    public func delete<Entity: DatabaseEntity>(_: Entity.Type, ids: [Entity.Model.ID]) throws {
        guard !ids.isEmpty else { return }

        try write {
            try applyDeletions(ids, of: Entity.self)
        }
        logger.log(.info, "Database write: deleted \(ids.count) \(Entity.self)")
    }

    /// Fetches and deletes one by one rather than issuing a batch delete, so relationship delete rules
    /// run and CloudKit sees every deletion.
    public func deleteAll<Entity: DatabaseEntity>(_: Entity.Type) throws {
        try write {
            for entity in try modelContext.fetch(FetchDescriptor<Entity>()) {
                modelContext.delete(entity)
            }
        }
        logger.log(.info, "Database write: deleted every \(Entity.self)")
    }

    /// Applies a batch — typically one round of remote changes — in a single save.
    ///
    /// A sync round trip is exactly where the same id arrives twice, so every incoming model upserts.
    public func apply<Entity: DatabaseEntity>(_ changes: DatabaseChangeSet<Entity.Model>, to _: Entity.Type) throws {
        guard !changes.isEmpty else { return }

        try write {
            try applyUpserts(changes.upserts, as: Entity.self)
            try applyDeletions(changes.deletions, of: Entity.self)
        }
        logger.log(
            .info,
            "Database write: batch applied to \(Entity.self) — \(changes.upserts.count) upserted, \(changes.deletions.count) deleted"
        )
    }

    /// Flushes whatever the context is holding. Writes made through ``perform(_:)`` are the only ones
    /// that can leave something unsaved.
    public func save() throws {
        guard modelContext.hasChanges else { return }

        try write {}
    }

    /// Direct access to the context, for what the typed API does not cover — relationships, custom
    /// predicates over several entities, a custom migration step. Save before returning; never return
    /// a `PersistentModel`.
    public func perform<Result: Sendable>(_ work: (ModelContext) throws -> Result) throws -> Result {
        try work(modelContext)
    }

    // MARK: - Private

    private func entity<Entity: DatabaseEntity>(_: Entity.Type, id: Entity.Model.ID) throws -> Entity? {
        var descriptor = FetchDescriptor<Entity>(predicate: Entity.predicate(id: id))
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }

    /// One fetch for the whole batch, rather than one per model.
    private func applyUpserts<Entity: DatabaseEntity>(_ models: [Entity.Model], as _: Entity.Type) throws {
        guard !models.isEmpty else { return }

        let descriptor = FetchDescriptor<Entity>(predicate: Entity.predicate(ids: models.map(\.id)))
        var existing = Dictionary(
            try modelContext.fetch(descriptor).map { ($0[keyPath: Entity.idKeyPath], $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for model in models {
            if let entity = existing[model.id] {
                entity.update(with: model)
            } else {
                let entity = Entity(model: model)
                modelContext.insert(entity)
                existing[model.id] = entity
            }
        }
    }

    private func applyDeletions<Entity: DatabaseEntity>(_ ids: [Entity.Model.ID], of _: Entity.Type) throws {
        guard !ids.isEmpty else { return }

        for entity in try modelContext.fetch(FetchDescriptor<Entity>(predicate: Entity.predicate(ids: ids))) {
            modelContext.delete(entity)
        }
    }

    private func write(_ changes: () throws -> Void) throws {
        do {
            try changes()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logger.log(.error, "Database write failed and was rolled back: \(error)")
            throw error
        }
    }
}

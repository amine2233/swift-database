import DatabaseKit
import Foundation
import SwiftData

struct Note: Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, body: String = "", createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

enum NoteSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [NoteEntity.self] }

    @Model
    final class NoteEntity {
        var id: UUID = UUID()
        var title: String = ""
        var createdAt: Date = Date.now

        init(id: UUID, title: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
        }
    }
}

enum NoteSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [NoteEntity.self] }

    @Model
    final class NoteEntity {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var createdAt: Date = Date.now

        init(id: UUID, title: String, body: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.body = body
            self.createdAt = createdAt
        }
    }
}

typealias NoteEntity = NoteSchemaV2.NoteEntity

extension NoteEntity: DatabaseEntity {
    static var idKeyPath: any KeyPath<NoteEntity, UUID> & Sendable { \.id }

    convenience init(model: Note) {
        self.init(id: model.id, title: model.title, body: model.body, createdAt: model.createdAt)
    }

    func makeModel() -> Note {
        Note(id: id, title: title, body: body, createdAt: createdAt)
    }

    func update(with model: Note) {
        title = model.title
        body = model.body
        createdAt = model.createdAt
    }
}

enum NoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NoteSchemaV1.self, NoteSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: NoteSchemaV1.self, toVersion: NoteSchemaV2.self)]
    }
}

enum NoteSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { NoteSchemaV2.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { NoteMigrationPlan.self }
}

/// The store as the first release shipped it, before `body` existed.
enum NoteSchemaFirstRelease: DatabaseSchema {
    static var models: [any PersistentModel.Type] { NoteSchemaV1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { NoteMigrationPlanFirstRelease.self }
}

enum NoteMigrationPlanFirstRelease: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NoteSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// A store whose `title` became an `Int`: no migration can be inferred from the current file.
enum NoteSchemaIncompatible: DatabaseSchema {
    enum V1: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)
        static var models: [any PersistentModel.Type] { [NoteEntity.self] }

        @Model
        final class NoteEntity {
            var id: UUID = UUID()
            var title: Int = 0

            init() {}
        }
    }

    enum Plan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [V1.self] }
        static var stages: [MigrationStage] { [] }
    }

    static var models: [any PersistentModel.Type] { V1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { Plan.self }
}

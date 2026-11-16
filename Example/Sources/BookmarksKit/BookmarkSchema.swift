import DatabaseKit
import Foundation
import SwiftData

/// Every attribute has a default and none is unique, so the store can turn on CloudKit later without
/// a migration.
public enum BookmarkSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [BookmarkEntity.self]
    }

    @Model
    public final class BookmarkEntity {
        public var id: UUID = UUID()
        public var title: String = ""
        public var urlString: String = ""
        public var source: String = Bookmark.Source.app.rawValue
        public var createdAt: Date = Date.now

        init(id: UUID, title: String, urlString: String, source: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.urlString = urlString
            self.source = source
            self.createdAt = createdAt
        }
    }
}

public typealias BookmarkEntity = BookmarkSchemaV1.BookmarkEntity

extension BookmarkEntity: DatabaseEntity {
    public static var idKeyPath: any KeyPath<BookmarkEntity, UUID> & Sendable { \.id }

    public convenience init(model: Bookmark) {
        self.init(
            id: model.id,
            title: model.title,
            urlString: model.url.absoluteString,
            source: model.source.rawValue,
            createdAt: model.createdAt
        )
    }

    public func makeModel() -> Bookmark {
        Bookmark(
            id: id,
            title: title,
            url: URL(string: urlString) ?? URL(filePath: "/"),
            source: Bookmark.Source(rawValue: source) ?? .app,
            createdAt: createdAt
        )
    }

    public func update(with model: Bookmark) {
        title = model.title
        urlString = model.url.absoluteString
        source = model.source.rawValue
        createdAt = model.createdAt
    }
}

public enum BookmarkMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [BookmarkSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum BookmarkSchema: DatabaseSchema {
    public static var models: [any PersistentModel.Type] { BookmarkSchemaV1.models }
    public static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}

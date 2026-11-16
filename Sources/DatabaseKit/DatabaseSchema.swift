import SwiftData

/// The models a store holds, and how its older versions reach the current one.
///
/// One conforming type per app (or per store). Keep the versioned schemas and the migration plan next
/// to it, and point ``models`` at the latest version:
///
/// ```swift
/// enum BookmarkSchema: DatabaseSchema {
///     static let models: [any PersistentModel.Type] = BookmarkSchemaV2.models
///     static let migrationPlan: (any SchemaMigrationPlan.Type)? = BookmarkMigrationPlan.self
/// }
/// ```
public protocol DatabaseSchema: SendableMetatype {
    /// The current version's models.
    static var models: [any PersistentModel.Type] { get }

    /// `nil` for a store that has never shipped a second version.
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { get }
}

extension DatabaseSchema {
    public static var migrationPlan: (any SchemaMigrationPlan.Type)? { nil }

    static var schema: Schema {
        Schema(models)
    }
}

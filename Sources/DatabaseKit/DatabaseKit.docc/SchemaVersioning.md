# Schema Versioning

Evolve a shipped store with versioned schemas and a migration plan, without losing user data.

## Overview

Once a store has shipped, its file on disk was written by a specific version of your models. To
change the models you add a new `VersionedSchema`, describe how to reach it in a
`SchemaMigrationPlan`, and point ``DatabaseSchema/models`` at the new version. When the store opens,
SwiftData walks the plan from the file's version to the current one.

The rules:

- **Never edit a version that has shipped.** Copy it into a new version and change the copy.
- **Append, never reorder.** `schemas` and `stages` list every version from the first release on.
- **Only the current entity conforms to ``DatabaseEntity``.** Older versions exist so SwiftData can
  read old files.
- **Move the `typealias`** to the newest version so the rest of the app keeps compiling.

### Version 1 — the first release

```swift
enum BookmarkSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

    @Model
    final class BookmarkEntity {
        var id: UUID = UUID()
        var title: String = ""
        var url: URL = URL(string: "about:blank")!  // A literal that always parses.

        init(id: UUID, title: String, url: URL) {
            self.id = id
            self.title = title
            self.url = url
        }
    }
}

enum BookmarkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BookmarkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias BookmarkEntity = BookmarkSchemaV1.BookmarkEntity

enum BookmarkSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { BookmarkSchemaV1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}
```

### Version 2 — a lightweight migration

Adding a property with a default, removing one, or renaming one with
`@Attribute(originalName:)` is inferred by SwiftData: a `lightweight` stage is enough.

```swift
enum BookmarkSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

    @Model
    final class BookmarkEntity {
        var id: UUID = UUID()
        var title: String = ""
        @Attribute(originalName: "url") var address: URL = URL(string: "about:blank")!  // Always parses.
        var createdAt: Date = Date.now
        var notes: String = ""

        init(id: UUID, title: String, address: URL, createdAt: Date, notes: String) {
            self.id = id
            self.title = title
            self.address = address
            self.createdAt = createdAt
            self.notes = notes
        }
    }
}

enum BookmarkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookmarkSchemaV1.self, BookmarkSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: BookmarkSchemaV1.self, toVersion: BookmarkSchemaV2.self)]
    }
}

typealias BookmarkEntity = BookmarkSchemaV2.BookmarkEntity

enum BookmarkSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { BookmarkSchemaV2.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}
```

Update the model and the ``DatabaseEntity`` conformance to match:

```swift
struct Bookmark: Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var url: URL
    var createdAt: Date
    var notes: String
}

extension BookmarkEntity: DatabaseEntity {
    static var idKeyPath: any KeyPath<BookmarkEntity, UUID> & Sendable { \.id }

    convenience init(model: Bookmark) {
        self.init(id: model.id, title: model.title, address: model.url, createdAt: model.createdAt, notes: model.notes)
    }

    func makeModel() -> Bookmark {
        Bookmark(id: id, title: title, url: address, createdAt: createdAt, notes: notes)
    }

    func update(with model: Bookmark) {
        title = model.title
        address = model.url
        createdAt = model.createdAt
        notes = model.notes
    }
}
```

### Version 3 — a custom migration

When new data has to be computed from old data, use a `custom` stage. The schema change itself
stays lightweight-compatible (a new property with a default); `didMigrate` then fills it in, on the
new version's entities.

```swift
enum BookmarkSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

    @Model
    final class BookmarkEntity {
        var id: UUID = UUID()
        var title: String = ""
        var address: URL = URL(string: "about:blank")!  // A literal that always parses.
        var host: String = ""
        var createdAt: Date = Date.now
        var notes: String = ""

        init(id: UUID, title: String, address: URL, host: String, createdAt: Date, notes: String) {
            self.id = id
            self.title = title
            self.address = address
            self.host = host
            self.createdAt = createdAt
            self.notes = notes
        }
    }
}

enum BookmarkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookmarkSchemaV1.self, BookmarkSchemaV2.self, BookmarkSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: BookmarkSchemaV1.self, toVersion: BookmarkSchemaV2.self),
            .custom(
                fromVersion: BookmarkSchemaV2.self,
                toVersion: BookmarkSchemaV3.self,
                willMigrate: nil,
                didMigrate: { context in
                    for bookmark in try context.fetch(FetchDescriptor<BookmarkSchemaV3.BookmarkEntity>()) {
                        bookmark.host = bookmark.address.host() ?? ""
                    }
                    try context.save()
                }
            ),
        ]
    }
}

typealias BookmarkEntity = BookmarkSchemaV3.BookmarkEntity

enum BookmarkSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { BookmarkSchemaV3.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}
```

Give `Bookmark` a `host` property and map it in the ``DatabaseEntity`` conformance, as for
version 2.

A device still on version 1 runs both stages in order the first time it opens the store.

> Tip: To clean up data *before* the schema changes — removing duplicates ahead of a change that
> relies on them being unique, for example — do it in `willMigrate`, which runs on the old version's
> entities.

### Stores that mirror to CloudKit

CloudKit only accepts additive changes, and the schema it holds is shared by every device, whatever
version it runs:

- Every property needs a default value or must be optional; every relationship must be optional.
- Never use `@Attribute(.unique)` — identity goes through ``DatabaseEntity/idKeyPath`` instead.
- Add properties and entities; do not delete, rename or change the type of one already deployed to
  the production CloudKit environment. Older app versions keep writing the old fields.
- Deploy the new schema to production from the CloudKit Console before shipping the release.

### Files no migration can reach

If a file's version matches no schema in the plan — a model changed without a new version, or a
build downgraded below the store's version — the store cannot open, and
``DatabaseDefault/init(configuration:logger:)`` throws. ``IncompatibleStorePolicy`` decides what
happens next:

```swift
// User content: keep the file, let makeOrEphemeral degrade to memory and report the error.
let notes = DatabaseConfiguration(
    name: "Notes",
    schema: NoteSchema.self,
    location: .group("group.com.example.notes"),
    incompatibleStorePolicy: .fail
)

// A cache that can be refetched: start empty instead.
let thumbnails = DatabaseConfiguration(
    name: "Thumbnails",
    schema: ThumbnailSchema.self,
    location: .main,
    incompatibleStorePolicy: .deleteAndRecreate
)
```

``IncompatibleStorePolicy/deleteAndRecreate`` deletes the file — together with its `-wal` and `-shm`
companions — only when the file's own metadata matches no version the plan knows. A file whose
metadata cannot be read right now, such as a protected file while the device is locked, is never
treated as incompatible and never deleted.

> Warning: ``IncompatibleStorePolicy/deleteAndRecreate`` destroys data. Use it only for stores whose
> content can be rebuilt.

### Test every migration

Seed a file with the shipped version, open it with the current schema and check the rows survived.
See *Testing Schema Versions* in the `DatabaseKitTesting` documentation.

# Getting Started

Add DatabaseKit, describe one model, open the store and read and write through a repository.

## Overview

A DatabaseKit store is made of four pieces:

1. A `Sendable` **model** — the value your features pass around.
2. A SwiftData **entity** — a `@Model` class conforming to ``DatabaseEntity`` that maps to and from
   the model.
3. A **schema** — a type conforming to ``DatabaseSchema`` that lists the current models and the
   migration plan.
4. A **configuration** — a ``DatabaseConfiguration`` naming the store and where its file lives.

### Add the package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/amine2233/swift-database.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "BookmarksKit",
        dependencies: [.product(name: "DatabaseKit", package: "swift-database")]
    ),
    .testTarget(
        name: "BookmarksKitTests",
        dependencies: [
            "BookmarksKit",
            .product(name: "DatabaseKitTesting", package: "swift-database"),
        ]
    ),
]
```

### Define the model

The model is what features see. It only needs to be `Identifiable` and `Sendable`, with a `Codable`
identifier.

```swift
import Foundation

struct Bookmark: Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var url: URL
}
```

### Define the entity inside a versioned schema

Declare the `@Model` class inside its first `VersionedSchema`, even if you have no second version
yet: the day you need one, the first version is already frozen. See <doc:SchemaVersioning>.

```swift
import DatabaseKit
import Foundation
import SwiftData

enum BookmarkSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

    @Model
    final class BookmarkEntity {
        // A default on every property and no `.unique`: both are required by CloudKit.
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

typealias BookmarkEntity = BookmarkSchemaV1.BookmarkEntity

extension BookmarkEntity: DatabaseEntity {
    static var idKeyPath: any KeyPath<BookmarkEntity, UUID> & Sendable { \.id }

    convenience init(model: Bookmark) {
        self.init(id: model.id, title: model.title, url: model.url)
    }

    func makeModel() -> Bookmark {
        Bookmark(id: id, title: title, url: url)
    }

    func update(with model: Bookmark) {
        title = model.title
        url = model.url
    }
}
```

``DatabaseEntity/idKeyPath`` is how DatabaseKit finds an existing row: `upsert`
updates the row carrying the same id instead of inserting a duplicate.

### Declare the schema

```swift
enum BookmarkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BookmarkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum BookmarkSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { BookmarkSchemaV1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}
```

``DatabaseSchema/migrationPlan`` defaults to `nil`, but declaring a plan from the first release lets
DatabaseKit tell a known older file from an incompatible one.

### Choose where the file lives

``DatabaseConfiguration/location`` has no default, because it decides which processes can ever see
the data:

| Location | Visible to | Use it when |
| --- | --- | --- |
| ``StoreLocation/main`` | Only the process that opened it | No extension reads or writes this data, ever |
| ``StoreLocation/group(_:)`` | The app and every extension in the App Group | A share, Safari, widget or intent extension needs the data |
| ``StoreLocation/url(_:)`` | Whoever opens that path | Test fixtures and repair copies — never mirrored |
| ``StoreLocation/inMemory`` | The container only | Previews and tests |

> Important: An extension opening `.main` silently gets its own, empty file. If an extension might
> ever touch this data, start with `.group` — moving an existing `.main` store means copying the
> file yourself.

### Open the store once per process

```swift
enum AppDatabase {
    static let configuration = DatabaseConfiguration(
        name: "Bookmarks",
        schema: BookmarkSchema.self,
        location: .group("group.com.example.bookmarks")
    )

    static let shared = DatabaseDefault.makeOrEphemeral(configuration: configuration) { error in
        // Report to crash or analytics tooling.
    }

    static var bookmarks: some Repository<Bookmark> {
        shared.repository(for: BookmarkEntity.self)
    }
}
```

``DatabaseDefault/makeOrEphemeral(configuration:logger:onFailure:)`` never traps: if the file is
corrupt or a migration throws, it returns an in-memory store whose ``Database/isEphemeral`` is
`true`. Tell the user nothing is being saved. Use ``DatabaseDefault/init(configuration:logger:)``
instead to handle the error yourself.

### Read and write

```swift
let bookmarks = AppDatabase.bookmarks

let swift = Bookmark(id: UUID(), title: "Swift", url: URL(string: "https://swift.org")!)  // Valid literal.
try await bookmarks.upsert(swift)

let all = try await bookmarks.fetchAll()
let one = try await bookmarks.fetch(id: swift.id)

try await bookmarks.delete(id: swift.id)
```

Continue with <doc:ExampleUsage> for filtering, batches, SwiftUI, extensions and CloudKit.

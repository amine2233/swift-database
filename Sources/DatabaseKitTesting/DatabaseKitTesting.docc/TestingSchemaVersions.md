# Testing Schema Versions

Prove that a store written by a shipped release still opens, with its rows, under the current
schema.

## Overview

A migration test writes a file with an old version of the schema, then reopens the same file with
the current one. It needs a real store on disk, so it uses `DatabaseDefault` with
`StoreLocation.url(_:)` rather than ``RepositoryMock``.

The examples assume the `BookmarkSchemaV1` → `BookmarkSchemaV2` → `BookmarkSchemaV3` history from
the *Schema Versioning* article in the DatabaseKit documentation.

### Give each test its own directory

```swift
import Foundation

struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "BookmarksTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var storeURL: URL {
        url.appending(path: "Bookmarks.store")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
```

### Freeze each shipped release as a schema

A `DatabaseSchema` whose models and plan stop at an old version reproduces exactly what that release
wrote. Keep one per shipped version, in the test target:

```swift
import DatabaseKit
import SwiftData

/// The store as release 1.0 wrote it.
enum BookmarkSchemaRelease1: DatabaseSchema {
    enum Plan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [BookmarkSchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }

    static var models: [any PersistentModel.Type] { BookmarkSchemaV1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { Plan.self }
}

/// The store as release 2.0 wrote it.
enum BookmarkSchemaRelease2: DatabaseSchema {
    enum Plan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [BookmarkSchemaV1.self, BookmarkSchemaV2.self] }
        static var stages: [MigrationStage] {
            [.lightweight(fromVersion: BookmarkSchemaV1.self, toVersion: BookmarkSchemaV2.self)]
        }
    }

    static var models: [any PersistentModel.Type] { BookmarkSchemaV2.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { Plan.self }
}

extension DatabaseConfiguration {
    static func bookmarks(at url: URL, schema: any DatabaseSchema.Type = BookmarkSchema.self) -> Self {
        DatabaseConfiguration(name: "Bookmarks", schema: schema, location: .url(url))
    }
}
```

Old entities do not conform to `DatabaseEntity`, so seed them through
`DatabaseActor.perform(_:)`.

### Test each upgrade path

```swift
@testable import BookmarksKit
import DatabaseKit
import Foundation
import SwiftData
import Testing

@Suite("Bookmark migrations")
struct BookmarkMigrationTests {
    @Test func aRelease1StoreReachesTheCurrentVersion() async throws {
        let directory = try TemporaryDirectory()
        let id = UUID()
        let old = try DatabaseDefault(configuration: .bookmarks(at: directory.storeURL, schema: BookmarkSchemaRelease1.self))
        try await old.modelActor().perform { context in
            context.insert(BookmarkSchemaV1.BookmarkEntity(
                id: id,
                title: "Swift",
                url: URL(string: "https://swift.org")!  // Valid literal.
            ))
            try context.save()
        }

        let current = try DatabaseDefault(configuration: .bookmarks(at: directory.storeURL))
        let migrated = try await current.repository(for: BookmarkEntity.self).fetch(id: id)

        #expect(migrated?.title == "Swift")
        #expect(migrated?.url.absoluteString == "https://swift.org")
        #expect(migrated?.notes == "")
    }

    @Test func theCustomStageFillsInTheHost() async throws {
        let directory = try TemporaryDirectory()
        let id = UUID()
        let old = try DatabaseDefault(configuration: .bookmarks(at: directory.storeURL, schema: BookmarkSchemaRelease2.self))
        try await old.modelActor().perform { context in
            context.insert(BookmarkSchemaV2.BookmarkEntity(
                id: id,
                title: "Swift",
                address: URL(string: "https://swift.org/blog")!,  // Valid literal.
                createdAt: .now,
                notes: ""
            ))
            try context.save()
        }

        let current = try DatabaseDefault(configuration: .bookmarks(at: directory.storeURL))
        let host = try await current.modelActor().perform { context in
            try context.fetch(FetchDescriptor<BookmarkEntity>()).first?.host
        }

        #expect(host == "swift.org")
    }
}
```

Open the old store and the new one from separate `DatabaseDefault` instances, as above: each test
stands for a user upgrading the app, so the old container has to be gone before the new one opens.

### Test the incompatible-store policy

A schema that no stage can reach must fail by default, and must start empty only when the
configuration allows it:

```swift
/// `title` became an `Int` without a new version: nothing can migrate the current file.
enum BookmarkSchemaIncompatible: DatabaseSchema {
    enum V1: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)
        static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

        @Model
        final class BookmarkEntity {
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

@Suite("Incompatible stores")
struct IncompatibleStoreTests {
    @Test func anUnknownVersionFailsByDefault() async throws {
        let directory = try TemporaryDirectory()
        try await DatabaseDefault(configuration: .bookmarks(at: directory.storeURL))
            .repository(for: BookmarkEntity.self)
            .upsert(Bookmark(id: UUID(), title: "Kept", url: URL(string: "https://swift.org")!))  // Valid literal.

        #expect(throws: (any Error).self) {
            try DatabaseDefault(configuration: .bookmarks(at: directory.storeURL, schema: BookmarkSchemaIncompatible.self))
        }
    }

    @Test func anUnknownVersionIsRecreatedWhenAllowed() async throws {
        let directory = try TemporaryDirectory()
        try await DatabaseDefault(configuration: .bookmarks(at: directory.storeURL))
            .repository(for: BookmarkEntity.self)
            .upsert(Bookmark(id: UUID(), title: "Dropped", url: URL(string: "https://swift.org")!))  // Valid literal.
        var configuration = DatabaseConfiguration.bookmarks(at: directory.storeURL, schema: BookmarkSchemaIncompatible.self)
        configuration.incompatibleStorePolicy = .deleteAndRecreate

        let database = try DatabaseDefault(configuration: configuration)
        let count = try await database.modelActor().perform { context in
            try context.fetchCount(FetchDescriptor<BookmarkSchemaIncompatible.V1.BookmarkEntity>())
        }

        #expect(count == 0)
    }
}
```

### Keep a fixture from every release

Generated stores only cover what today's code can write. For extra confidence, copy a real store
file from each shipped release into the test bundle, copy it into a `TemporaryDirectory` at the
start of the test, and open it with the current schema the same way.

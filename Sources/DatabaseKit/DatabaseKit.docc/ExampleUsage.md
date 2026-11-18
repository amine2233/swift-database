# Example Usage

Common tasks: queries, batches, SwiftUI, app extensions, widgets, CloudKit and escaping to the
`ModelContext`.

## Overview

The examples build on the `Bookmark` model, `BookmarkEntity` and `AppDatabase` from
<doc:GettingStarted>.

### Depend on the protocol

Features take `any Repository<Bookmark>`, not ``RepositoryDefault``, so tests can hand them
`RepositoryMock` from `DatabaseKitTesting`.

```swift
import DatabaseKit
import Observation

@MainActor
@Observable
final class BookmarkListModel {
    private(set) var bookmarks: [Bookmark] = []
    private(set) var errorMessage: String?

    private let repository: any Repository<Bookmark>

    init(repository: any Repository<Bookmark>) {
        self.repository = repository
    }

    func reload() async {
        do {
            bookmarks = try await repository.fetchAll().sorted { $0.title < $1.title }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ bookmark: Bookmark) async {
        do {
            try await repository.upsert(bookmark)
            bookmarks.append(bookmark)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ ids: [Bookmark.ID]) async {
        do {
            try await repository.delete(ids: ids)
            bookmarks.removeAll { ids.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Show it in SwiftUI

Each process has its own `ModelContext`, so a write made by an extension appears the next time the
app fetches. Reload whenever the scene becomes active, and tell the user when the store is
ephemeral.

```swift
import SwiftUI

struct BookmarkListView: View {
    @State private var model: BookmarkListModel
    @Environment(\.scenePhase) private var scenePhase

    init(model: BookmarkListModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                if AppDatabase.shared.isEphemeral {
                    Label("Bookmarks are not being saved.", systemImage: "exclamationmark.triangle")
                }
                ForEach(model.bookmarks) { bookmark in
                    Text(bookmark.title)
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.bookmarks[$0].id }
                    Task { await model.delete(ids) }
                }
            }
            .navigationTitle("Bookmarks")
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.reload() }
        }
    }
}

// In the app scene:
BookmarkListView(model: BookmarkListModel(repository: AppDatabase.bookmarks))
```

### Insert, update and delete

```swift
let bookmarks = AppDatabase.bookmarks

// Inserts, or updates the row already carrying the same id.
try await bookmarks.upsert([first, second])

// Updates only: throws DatabaseError.notFound instead of resurrecting a row another device deleted.
do {
    try await bookmarks.update(edited)
} catch DatabaseError.notFound {
    // The bookmark is gone; drop the edit.
}

try await bookmarks.delete(ids: [first.id, second.id])
try await bookmarks.deleteAll()
```

### Apply a batch in one save

``DatabaseChangeSet`` groups upserts and deletions — typically one round of changes from a server —
into a single save that either fully succeeds or rolls back.

```swift
let changes = DatabaseChangeSet<Bookmark>(
    upserts: response.updated,
    deletions: response.removedIDs
)
try await AppDatabase.bookmarks.apply(changes)
```

### Filter, sort and page

Predicates and sort descriptors are written against the entity, so they live on
``RepositoryDefault`` rather than on ``Repository``.

```swift
let repository = AppDatabase.shared.repository(for: BookmarkEntity.self)

var descriptor = FetchDescriptor<BookmarkEntity>(
    predicate: #Predicate { $0.title.localizedStandardContains("swift") },
    sortBy: [SortDescriptor(\.title)]
)
descriptor.fetchLimit = 20
descriptor.fetchOffset = 40

let page = try await repository.fetch(descriptor)
let matches = try await repository.count(descriptor)
```

### Use the context directly

For what the typed API does not cover — relationships, queries across several entities, bulk
fix-ups — use ``DatabaseActor/perform(_:)``. Save before returning and return only `Sendable`
values, never a `PersistentModel`.

```swift
let renamed = try await AppDatabase.shared.modelActor().perform { context in
    let untitled = try context.fetch(FetchDescriptor<BookmarkEntity>(
        predicate: #Predicate { $0.title.isEmpty }
    ))
    for entity in untitled {
        entity.title = entity.url.host() ?? entity.url.absoluteString
    }
    try context.save()

    return untitled.count
}
```

### Share the store with extensions

Build the **same** configuration in every target — same ``DatabaseConfiguration/name``, same
``StoreLocation/group(_:)`` — ideally from one shared framework, and add the App Groups entitlement
with that identifier to the app and every extension.

```swift
// ShareViewController.swift, in the share extension.
func save(_ url: URL, title: String) async throws {
    let bookmark = Bookmark(id: UUID(), title: title, url: url)
    try await AppDatabase.bookmarks.upsert(bookmark)
}
```

> Warning: Never derive ``DatabaseConfiguration/name`` from `Bundle.main.bundleIdentifier`. Each
> extension has its own bundle identifier and would open a second store.

### Read-only widgets

A widget should never write to a store the app owns. Copy the configuration and turn saving off:

```swift
var widgetConfiguration = AppDatabase.configuration
widgetConfiguration.allowsSave = false

let database = DatabaseDefault.makeOrEphemeral(configuration: widgetConfiguration)
let recent = try await database.repository(for: BookmarkEntity.self).fetchAll()
```

### Mirror to CloudKit

```swift
let configuration = DatabaseConfiguration(
    name: "Bookmarks",
    schema: BookmarkSchema.self,
    location: .group("group.com.example.bookmarks"),
    cloudKit: CloudKitSync(container: .identifier("iCloud.com.example.bookmarks"))
)

// Later, once the user's entitlement is known:
try await AppDatabase.shared.setCloudKitEnabled(subscription.isActive)
```

- Mirroring is off at launch by default (``CloudKitSync/isEnabledAtLaunch``), so a paid feature
  never exports for a lapsed subscriber before the check completes.
- ``Database/setCloudKitEnabled(_:)`` rebuilds the container against the same file — no copy, no
  migration. Repositories pick up the new container on their next call.
- It is a no-op for ``StoreLocation/url(_:)`` and ``StoreLocation/inMemory`` stores, and inside test
  hosts, where building a CloudKit container aborts the process.
- Mirror from the app only. Extensions open the same configuration but never enable sync; the app
  exports their writes.

### Log what the store does

Every read, write and container change is reported through a ``DatabaseLogger``.
``DatabaseLoggerDefault`` writes to `os.Logger`; pass your own subsystem, or your own logger.

```swift
let logger = DatabaseLoggerDefault(subsystem: "com.example.bookmarks", category: "Database")
let database = DatabaseDefault.makeOrEphemeral(configuration: AppDatabase.configuration, logger: logger)
logger.log(.info, "Bookmarks store: \(database.storeURL.path)")
```

### Previews

```swift
#Preview {
    BookmarkListView(model: BookmarkListModel(
        repository: DatabaseDefault.ephemeral(schema: BookmarkSchema.self).repository(for: BookmarkEntity.self)
    ))
}
```

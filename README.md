# DatabaseKit

A reusable, protocol-based SwiftData layer for every Apple target: iOS, iPadOS, macOS, tvOS, watchOS,
visionOS, and app extensions (share, Safari web extension, widgets…).

- **One configuration** shared by the app and its extensions, so they all open the same file.
- **Value types only** across the boundary: `@Model` objects never leave the `DatabaseActor`.
- **CloudKit-ready**: upsert by your own id (CloudKit forbids `@Attribute(.unique)`), and sync can be
  turned on and off at runtime.
- **Never traps at launch**: a store that won't open degrades to memory and says so.
- **Testable**: features depend on `Repository`, and tests use `RepositoryMock` from `DatabaseKitTesting`.

Requires Swift 6.2+, iOS 18 / macOS 15 / tvOS 18 / watchOS 11 / visionOS 2.

---

## 1. Choose where the file lives: `.main` or `.group`

This is the decision that matters most, and it is why `location` has **no default**. It controls which
processes can ever see the data, and moving an existing store later means copying the file yourself.

| | `.main` | `.group("group.com.you.app")` |
|---|---|---|
| File | `<this process's container>/Library/Application Support/<name>.store` | `<App Group container>/Library/Application Support/<name>.store` |
| Visible to | **Only the process that opened it** | The app **and every extension** with the same App Group |
| Entitlement | None | App Groups (`com.apple.security.application-groups`) on every target |
| CloudKit | ✅ | ✅ |
| Pick it when | The app has no extension that reads or writes this data, and never will | A share/Safari/widget/intent extension needs the data, now or in a future release |

**Rule of thumb:** if you have, or might ever ship, an extension that touches this data, start with
`.group`. An extension opening `.main` gets its own empty file and no error, so the bug stays
invisible until a user reports it.

Two more locations exist, for special cases:

- `.url(URL)` opens a specific file. It never mirrors to CloudKit. Use it for test fixtures and repair copies.
- `.inMemory` lives as long as the container. It never mirrors and is never rebuilt. Use it for previews and tests.

To see which file a process actually opened, log `database.storeURL` once at launch.

### Setting up an App Group

1. In the Apple Developer portal (or Xcode › Signing & Capabilities), add the **App Groups** capability
   with the same identifier to the app **and every extension**.
2. iOS / iPadOS / tvOS / watchOS / visionOS: use `group.<reverse-dns>`.
3. macOS: sandboxed apps and extensions also need `com.apple.security.app-sandbox`. Since macOS 15, a
   `group.` identifier works when it is provisioned. Older systems expect `<TeamID>.<name>`.
4. Use the **same `name`** in every process. Never derive it from `Bundle.main.bundleIdentifier`,
   because an extension has its own bundle identifier and would open a different store.

---

## 2. Installation

```swift
.package(url: "https://github.com/<you>/swift-database.git", from: "1.0.0")

.target(name: "MyFeature", dependencies: [.product(name: "DatabaseKit", package: "swift-database")])
.testTarget(name: "MyFeatureTests", dependencies: [.product(name: "DatabaseKitTesting", package: "swift-database")])
```

---

## 3. Usage

### Model, entity, schema

```swift
import DatabaseKit
import SwiftData

// The Sendable value your features use.
struct Bookmark: Identifiable, Sendable {
    var id: UUID
    var title: String
}

enum BookmarkSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BookmarkEntity.self] }

    @Model
    final class BookmarkEntity {
        // Defaults everywhere and no `.unique`: required if CloudKit is ever turned on.
        var id: UUID = UUID()
        var title: String = ""
        init(id: UUID, title: String) { self.id = id; self.title = title }
    }
}

typealias BookmarkEntity = BookmarkSchemaV1.BookmarkEntity

extension BookmarkEntity: DatabaseEntity {
    static var idKeyPath: any KeyPath<BookmarkEntity, UUID> & Sendable { \.id }
    convenience init(model: Bookmark) { self.init(id: model.id, title: model.title) }
    func makeModel() -> Bookmark { Bookmark(id: id, title: title) }
    func update(with model: Bookmark) { title = model.title }
}

enum BookmarkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BookmarkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum BookmarkSchema: DatabaseSchema {
    static var models: [any PersistentModel.Type] { BookmarkSchemaV1.models }
    static var migrationPlan: (any SchemaMigrationPlan.Type)? { BookmarkMigrationPlan.self }
}
```

### Open the store, once per process

```swift
enum AppDatabase {
    static let configuration = DatabaseConfiguration(
        name: "Bookmarks",
        schema: BookmarkSchema.self,
        location: .group("group.com.you.bookmarks")   // or .main — see section 1
    )

    static let shared = DatabaseDefault.makeOrEphemeral(configuration: configuration) { error in
        // report to your crash/analytics tool
    }
}
```

`makeOrEphemeral` never traps. If the file is corrupt or a migration throws, you get an in-memory
store with `isEphemeral == true`. Show that in the UI, because nothing is being saved. Use
`try DatabaseDefault(configuration:)` if you would rather handle the error yourself.

### Read and write through a `Repository`

```swift
let bookmarks: any Repository<Bookmark> = AppDatabase.shared.repository(for: BookmarkEntity.self)

try await bookmarks.upsert(Bookmark(id: UUID(), title: "Swift"))   // insert or update by id
try await bookmarks.update(existing)                               // throws .notFound, never inserts
let all = try await bookmarks.fetchAll()
try await bookmarks.delete(id: existing.id)
try await bookmarks.apply(DatabaseChangeSet(upserts: remote, deletions: removedIDs))  // one save
```

`RepositoryDefault` also takes a `FetchDescriptor` when you need a predicate, sorting or paging:

```swift
var descriptor = FetchDescriptor<BookmarkEntity>(sortBy: [SortDescriptor(\.title)])
descriptor.fetchLimit = 20
let page = try await AppDatabase.shared.repository(for: BookmarkEntity.self).fetch(descriptor)
```

For anything the typed API doesn't cover (relationships, several entities at once), use
`try await database.modelActor().perform { context in … }`. Save before returning, and never return
a `PersistentModel`.

### CloudKit

```swift
DatabaseConfiguration(
    name: "Bookmarks",
    schema: BookmarkSchema.self,
    location: .group("group.com.you.bookmarks"),
    cloudKit: CloudKitSync(container: .identifier("iCloud.com.you.bookmarks"), isEnabledAtLaunch: false)
)

try await AppDatabase.shared.setCloudKitEnabled(subscription.isActive)
```

- Sync starts **off** by default, so a paid feature can enable it once the entitlement is confirmed.
- Turning it on or off rebuilds the container against the same file. There is no migration and no copy.
- It is a no-op for `.url`/`.inMemory` stores and inside test hosts, where a CloudKit container aborts the process.
- **Mirror from the app only.** Extensions should open the same configuration but never call
  `setCloudKitEnabled(true)`. Their writes go to the shared file and the app exports them.

### Read-only readers (widgets)

Set `allowsSave: false` on the configuration so a widget can never write to a store the app owns.

### Extensions: seeing each other's writes

Each process has its own context. When an extension writes, the app sees the change the next time it
fetches. Reload when the scene becomes `.active`, as the sample app does.

### Migrations

Add a `VersionedSchema`, append it to the plan with a `MigrationStage`, and point
`DatabaseSchema.models` at the new version. If no stage can reach a file's version, opening it throws.
`incompatibleStorePolicy: .deleteAndRecreate` wipes the file instead, but only on a genuine schema
mismatch (never on a transient error such as a locked device). Use it **only** for caches.

---

## 4. Testing

```swift
import DatabaseKitTesting

@Test func savesBookmark() async throws {
    let repository = RepositoryMock<Bookmark>()
    let model = BookmarkListModel(repository: repository)

    await model.add(title: "Swift", urlString: "swift.org")

    #expect(await repository.models.count == 1)
}

await repository.failNextCall(with: MyError())   // error paths
```

For integration tests against real SwiftData, use `location: .inMemory`, or `.url` in a temporary
directory when the test needs persistence or migration.

```bash
mise run test              # swift test (macOS)
mise run test-ios          # package tests on the first available iPhone simulator
mise run build-platforms   # iOS, tvOS, watchOS, visionOS, macOS
mise run build-example     # Tuist sample app for iOS, macOS, tvOS (unsigned)
mise run lint              # executor code + documentation lint
```

---

## 5. Sample app — `Example/`

A Bookmarks app showing one shared `.group` store used from four kinds of process:

| Target | Platforms | Shows |
|---|---|---|
| `Bookmarks` | iOS, iPadOS, macOS, tvOS | List/add/delete, reload on foreground, degraded-store banner |
| `BookmarksShareExtension` | iOS, iPadOS | Share a URL from any app → saved to the shared store |
| `BookmarksSafariExtension` | iOS, iPadOS, macOS | Popup → `sendNativeMessage` → native handler upserts |
| `BookmarksKit` | all | Schema, entity, the one `DatabaseConfiguration`, an `@Observable` list model |
| `BookmarksKitTests` | iOS, macOS | The list model tested with `RepositoryMock` |

```bash
cd Example
mise install          # pins Tuist (Example/mise.toml)
tuist generate        # opens Bookmarks.xcworkspace
```

Before running on a device, set your team and replace `com.example.databasekit.bookmarks` and
`group.com.example.databasekit.bookmarks` in `Project.swift` and `BookmarksDatabase.swift` with
identifiers you own. To try the Safari extension, enable it in Safari › Settings › Extensions (macOS)
or Settings › Apps › Safari › Extensions (iOS).

---

## 6. CI

CI uses [`amine2233/ci-shared`](https://github.com/amine2233/ci-shared). The workflows only run
`mise run <task>`, and every task is defined in [`mise.toml`](mise.toml). Run the same commands
locally to reproduce a CI failure.

| Workflow | Trigger | Runs |
|---|---|---|
| `ci.yml` (shared) | push / PR to `main` | `lint` and the PR title check (PRs only), `test` on macOS |
| `ci.yml` (`apple-platforms`) | push / PR to `main` | `test-ios`, `build-platforms`, `build-example` |
| `release.yml` | push to `main` | `release`: semantic-release tag, GitHub release, `CHANGELOG.md` |
| `pages.yml` | push to `main` | `build_documentations` → DocC on GitHub Pages |

- There is no Linux job because SwiftData is Apple-only. macOS jobs pin `macos-26` because the
  package needs Swift 6.2 / Xcode 26.
- PR titles must follow Conventional Commits (`feat:`, `fix:`, …), because they drive the release version.
- One-time repo setup: **Settings → Pages → Source = GitHub Actions**. If `main` is protected, give
  the release a bypass (see the ci-shared README, "let the release push to a protected `main`").

---

## Architecture

```
Repository<Model> (protocol)          ← features depend on this
 ├─ RepositoryDefault<Entity>         ← resolves the actor on every call
 └─ RepositoryMock<Model>             ← DatabaseKitTesting
Database (protocol)
 └─ DatabaseDefault (actor)           ← owns the replaceable ModelContainer, CloudKit switch
     └─ DatabaseActor (ModelActor)    ← the only place a ModelContext is touched
DatabaseConfiguration                 ← name, schema, StoreLocation, CloudKitSync, policies
DatabaseEntity (protocol)             ← @Model ⇄ Sendable value mapping + id key path
DatabaseSchema (protocol)             ← models + migration plan
DatabaseLogger (protocol)             ← DatabaseLoggerDefault uses os.Logger
DatabaseError                         ← the module's single error type
```

# Example Usage

Assert on state and calls, exercise error paths, and know when to use a real store instead.

## Overview

The examples test the `BookmarkListModel` from <doc:GettingStarted>, and share one URL:

```swift
let swiftURL = URL(string: "https://swift.org")!  // A literal that always parses.
```

### Assert on the resulting state

``RepositoryMock`` upserts by id, exactly like the real repository, so a second upsert of the same
id replaces the row instead of adding one.

```swift
@Test func upsertingTheSameIDReplacesTheRow() async throws {
    let id = UUID()
    let repository = RepositoryMock<Bookmark>()

    try await repository.upsert(Bookmark(id: id, title: "Old", url: swiftURL))
    try await repository.upsert(Bookmark(id: id, title: "New", url: swiftURL))

    #expect(await repository.models.map(\.title) == ["New"])
}
```

### Assert on the calls

``RepositoryMock/calls`` records every operation, including failed ones. Match the cases you care
about with pattern matching:

```swift
@Test func deleteRemovesOnlyTheSelectedBookmarks() async {
    let kept = Bookmark(id: UUID(), title: "Kept", url: swiftURL)
    let removed = Bookmark(id: UUID(), title: "Removed", url: swiftURL)
    let repository = RepositoryMock<Bookmark>(models: [kept, removed])
    let model = BookmarkListModel(repository: repository)

    await model.delete([removed.id])

    let calls = await repository.calls
    #expect(calls.count == 1)
    guard case let .delete(ids) = calls.first else {
        Issue.record("Expected a delete, got \(calls)")
        return
    }
    #expect(ids == [removed.id])
    #expect(await repository.models == [kept])
}
```

### Exercise error paths

``RepositoryMock/failNextCall(with:)`` makes the next operation throw instead of running, then
clears itself. The failed call is still recorded.

```swift
struct OfflineError: Error {}

@Test func aFailedSaveShowsAnError() async {
    let repository = RepositoryMock<Bookmark>()
    await repository.failNextCall(with: OfflineError())
    let model = BookmarkListModel(repository: repository)

    await model.add(Bookmark(id: UUID(), title: "Swift", url: swiftURL))

    #expect(model.errorMessage != nil)
    #expect(model.bookmarks.isEmpty)
    #expect(await repository.models.isEmpty)
}
```

`update` on a missing row throws `DatabaseError.notFound` on its own, as the real repository does:

```swift
@Test func editingADeletedBookmarkFails() async {
    let repository = RepositoryMock<Bookmark>()

    await #expect(throws: DatabaseError.notFound(entity: "Bookmark")) {
        try await repository.update(Bookmark(id: UUID(), title: "Gone", url: swiftURL))
    }
}
```

### Test a batch

```swift
@Test func applyUpsertsAndDeletesInOneCall() async throws {
    let stale = Bookmark(id: UUID(), title: "Stale", url: swiftURL)
    let fresh = Bookmark(id: UUID(), title: "Fresh", url: swiftURL)
    let repository = RepositoryMock<Bookmark>(models: [stale])

    try await repository.apply(DatabaseChangeSet(upserts: [fresh], deletions: [stale.id]))

    #expect(await repository.models == [fresh])
    #expect(await repository.calls.count == 1)
}
```

### When to use a real store

``RepositoryMock`` has no `FetchDescriptor`, no predicates and no migrations. For code that relies on
those, test against a real `DatabaseDefault`:

- `location: .inMemory` — fast, isolated, gone when the test ends.
- `location: .url(...)` in a temporary directory — when the test must reopen the file, for example
  to check a migration. See <doc:TestingSchemaVersions>.

```swift
@Test func searchMatchesTitles() async throws {
    let database = try DatabaseDefault(configuration: DatabaseConfiguration(
        name: "Bookmarks",
        schema: BookmarkSchema.self,
        location: .inMemory
    ))
    let repository = database.repository(for: BookmarkEntity.self)
    try await repository.upsert([
        Bookmark(id: UUID(), title: "Swift Testing", url: swiftURL),
        Bookmark(id: UUID(), title: "SwiftData", url: swiftURL),
    ])

    let matches = try await repository.fetch(FetchDescriptor<BookmarkEntity>(
        predicate: #Predicate { $0.title.localizedStandardContains("testing") }
    ))

    #expect(matches.map(\.title) == ["Swift Testing"])
}
```

CloudKit mirroring is always off inside a test host, so a configuration with
`CloudKitSync` is safe to use in tests.

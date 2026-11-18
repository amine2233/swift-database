# Getting Started

Replace a repository with ``RepositoryMock`` and test a feature without SwiftData.

## Overview

The pattern has two halves: production code takes `any Repository<Model>`, and the test passes a
``RepositoryMock`` in its place.

### Make the feature depend on the protocol

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
            bookmarks = try await repository.fetchAll()
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

The app passes `database.repository(for: BookmarkEntity.self)`; the test passes a mock.

### Write the first test

```swift
import DatabaseKitTesting
import Foundation
import Testing
@testable import BookmarksKit

@MainActor
struct BookmarkListModelTests {
    @Test func reloadShowsStoredBookmarks() async {
        let stored = Bookmark(id: UUID(), title: "Swift", url: URL(string: "https://swift.org")!)  // Valid literal.
        let repository = RepositoryMock<Bookmark>(models: [stored])
        let model = BookmarkListModel(repository: repository)

        await model.reload()

        #expect(model.bookmarks == [stored])
    }

    @Test func addSavesTheBookmark() async {
        let repository = RepositoryMock<Bookmark>()
        let model = BookmarkListModel(repository: repository)

        await model.add(Bookmark(id: UUID(), title: "Swift", url: URL(string: "https://swift.org")!))  // Valid literal.

        #expect(await repository.models.count == 1)
    }
}
```

``RepositoryMock`` is an actor, so reading ``RepositoryMock/models`` or ``RepositoryMock/calls``
takes an `await`.

### What the mock gives you

| Member | Use it to |
| --- | --- |
| ``RepositoryMock/init(models:)`` | Seed the rows the feature starts with |
| ``RepositoryMock/models`` | Assert on the resulting state |
| ``RepositoryMock/calls`` | Assert on which operations ran, in order |
| ``RepositoryMock/failNextCall(with:)`` | Make the next operation throw, to test error paths |

Continue with <doc:ExampleUsage> for call assertions and error paths, and
<doc:TestingSchemaVersions> for tests against a real store.

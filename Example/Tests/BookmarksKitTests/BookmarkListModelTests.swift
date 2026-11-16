@testable import BookmarksKit
import DatabaseKit
import DatabaseKitTesting
import Foundation
import Testing

@MainActor
@Suite("BookmarkListModel")
struct BookmarkListModelTests {
    struct Failure: Error {}

    @Test func reloadSortsNewestFirst() async throws {
        let old = Bookmark(title: "Old", url: try #require(URL(string: "https://a.com")), source: .app, createdAt: .distantPast)
        let new = Bookmark(title: "New", url: try #require(URL(string: "https://b.com")), source: .shareExtension)
        let model = BookmarkListModel(repository: RepositoryMock(models: [old, new]))

        await model.reload()

        #expect(model.bookmarks.map(\.title) == ["New", "Old"])
    }

    @Test func addNormalisesTheURLAndFallsBackToTheHostAsTitle() async throws {
        let repository = RepositoryMock<Bookmark>()
        let model = BookmarkListModel(repository: repository)

        let added = await model.add(title: "  ", urlString: "swift.org")

        #expect(added)
        let stored = try #require(await repository.models.first)
        #expect(stored.url.absoluteString == "https://swift.org")
        #expect(stored.title == "swift.org")
    }

    @Test func addRejectsAnInvalidURLWithoutWriting() async {
        let repository = RepositoryMock<Bookmark>()
        let model = BookmarkListModel(repository: repository)

        let added = await model.add(title: "x", urlString: "not a url")

        #expect(!added)
        #expect(model.errorMessage != nil)
        #expect(await repository.calls.isEmpty)
    }

    @Test func aFailedWriteIsReportedAndNotShown() async {
        let repository = RepositoryMock<Bookmark>()
        await repository.failNextCall(with: Failure())
        let model = BookmarkListModel(repository: repository)

        let added = await model.add(title: "x", urlString: "https://swift.org")

        #expect(!added)
        #expect(model.bookmarks.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test func deleteRemovesFromStoreAndList() async throws {
        let bookmark = Bookmark(title: "A", url: try #require(URL(string: "https://a.com")), source: .app)
        let repository = RepositoryMock(models: [bookmark])
        let model = BookmarkListModel(repository: repository)
        await model.reload()

        await model.delete([bookmark.id])

        #expect(model.bookmarks.isEmpty)
        #expect(await repository.models.isEmpty)
    }
}

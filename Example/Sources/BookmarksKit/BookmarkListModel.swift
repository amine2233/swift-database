import DatabaseKit
import Foundation
import Observation

/// Depends on `Repository`, not on SwiftData: the tests drive it with `RepositoryMock`.
@MainActor
@Observable
public final class BookmarkListModel {
    public private(set) var bookmarks: [Bookmark] = []
    public private(set) var errorMessage: String?

    private let repository: any Repository<Bookmark>

    public init(repository: any Repository<Bookmark>) {
        self.repository = repository
    }

    /// Called on appear and whenever the app returns to the foreground — an extension may have
    /// written to the shared store while the app was suspended.
    public func reload() async {
        await run {
            bookmarks = try await repository.fetchAll().sorted { $0.createdAt > $1.createdAt }
        }
    }

    @discardableResult
    public func add(title: String, urlString: String, source: Bookmark.Source = .app) async -> Bool {
        guard let url = Self.url(from: urlString) else {
            errorMessage = "“\(urlString)” is not a valid web address."
            return false
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(title: trimmed.isEmpty ? url.host() ?? url.absoluteString : trimmed, url: url, source: source)
        await run {
            try await repository.upsert(bookmark)
            bookmarks.insert(bookmark, at: 0)
        }

        return errorMessage == nil
    }

    public func delete(_ ids: [Bookmark.ID]) async {
        await run {
            try await repository.delete(ids: ids)
            bookmarks.removeAll { ids.contains($0.id) }
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// Accepts a bare host such as `swift.org`; only http(s) addresses with a host pass.
    public nonisolated static func url(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host()?.isEmpty == false else {
            return nil
        }

        return url
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            errorMessage = nil
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

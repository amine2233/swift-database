import BookmarksKit
import DatabaseKit
import Foundation
import SafariServices

/// Receives `browser.runtime.sendNativeMessage` calls from the extension's popup and writes to the
/// same `.group` store the app reads.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let request = SaveRequest(message: message)
        let reply = Reply(context: context)

        Task {
            reply.send(await Self.handle(request))
        }
    }

    private static func handle(_ request: SaveRequest?) async -> [String: Any] {
        guard let request, let url = BookmarkListModel.url(from: request.url) else {
            return ["ok": false, "error": "Missing or invalid URL"]
        }

        do {
            let title = request.title.isEmpty ? url.host() ?? url.absoluteString : request.title
            try await BookmarksDatabase.repository.upsert(Bookmark(title: title, url: url, source: .safariExtension))
            let count = try await BookmarksDatabase.repository.count()

            return ["ok": true, "count": count]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }
}

private struct SaveRequest: Sendable {
    let url: String
    let title: String

    init?(message: [String: Any]?) {
        guard let message, message["action"] as? String == "save", let url = message["url"] as? String else {
            return nil
        }

        self.url = url
        self.title = message["title"] as? String ?? ""
    }
}

/// `NSExtensionContext` is not `Sendable`, but Safari hands each request its own context and this is
/// the only thing that touches it after `beginRequest` returns — exactly once.
private struct Reply: @unchecked Sendable {
    let context: NSExtensionContext

    func send(_ payload: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [item])
    }
}

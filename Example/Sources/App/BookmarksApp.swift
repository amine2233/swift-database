import BookmarksKit
import SwiftUI

@main
struct BookmarksApp: App {
    @State private var model = BookmarkListModel(repository: BookmarksDatabase.repository)

    var body: some Scene {
        WindowGroup {
            BookmarkListView(model: model, isEphemeral: BookmarksDatabase.shared.isEphemeral)
        }
    }
}

import BookmarksKit
import SwiftUI

struct BookmarkListView: View {
    let model: BookmarkListModel
    let isEphemeral: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if isEphemeral {
                    Label("Storage unavailable — bookmarks will not be saved.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                ForEach(model.bookmarks) { bookmark in
                    BookmarkRow(bookmark: bookmark)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.delete([bookmark.id]) }
                            }
                        }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.bookmarks[$0].id }
                    Task { await model.delete(ids) }
                }
            }
            .overlay {
                if model.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark",
                        description: Text("Add one here, or share a page from Safari.")
                    )
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddBookmarkView(model: model)
            }
            .alert("Something went wrong", isPresented: isShowingError) {
                Button("OK") { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .refreshable { await model.reload() }
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }

            Task { await model.reload() }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && !isAdding },
            set: { if !$0 { model.dismissError() } }
        )
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bookmark.title)
                .font(.headline)
            Text(bookmark.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Label(bookmark.source.label, systemImage: bookmark.source.systemImage)
                .font(.caption2)
                .foregroundStyle(.tint)
        }
    }
}

private extension Bookmark.Source {
    var label: String {
        switch self {
        case .app: "Added in app"
        case .shareExtension: "Share extension"
        case .safariExtension: "Safari extension"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app"
        case .shareExtension: "square.and.arrow.up"
        case .safariExtension: "safari"
        }
    }
}

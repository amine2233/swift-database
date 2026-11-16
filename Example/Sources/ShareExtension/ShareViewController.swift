import BookmarksKit
import SwiftUI
import UIKit

/// The share extension's principal class has to be a `UIViewController`; everything it shows is
/// SwiftUI.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let model = BookmarkListModel(repository: BookmarksDatabase.repository)
        let view = ShareView(model: model, loadURL: { [weak self] in await self?.sharedURL() }) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// The completion-handler API, because only `URL` — which is `Sendable` — crosses back. The async
    /// `loadItem` returns `any NSSecureCoding`, whose sendability differs between SDK releases.
    private func sharedURL() async -> URL? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.canLoadObject(ofClass: URL.self) }
        guard let provider = providers.first else { return nil }

        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

private struct ShareView: View {
    let model: BookmarkListModel
    let loadURL: () async -> URL?
    let finish: () -> Void

    @State private var url: URL?
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                if let url {
                    Text(url.absoluteString)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Save to Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: finish)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url else { return }

                        Task {
                            if await model.add(title: title, urlString: url.absoluteString, source: .shareExtension) {
                                finish()
                            }
                        }
                    }
                    .disabled(url == nil)
                }
            }
        }
        .task {
            url = await loadURL()
            title = url?.host() ?? ""
        }
    }
}

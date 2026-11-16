@testable import DatabaseKit
import Foundation
import Testing

@Suite("StoreLocation")
struct StoreLocationTests {
    @Test func mainResolvesInsideTheProcessOwnApplicationSupport() {
        let url = resolvedURL(for: .main)

        #expect(url.lastPathComponent == "Notes.store")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    @Test func aURLLocationIsUsedVerbatim() throws {
        let directory = try TemporaryDirectory()

        #expect(resolvedURL(for: .url(directory.storeURL())) == directory.storeURL())
    }

    @Test(arguments: [StoreLocation.main, .group("group.test"), .url(URL(filePath: "/tmp/x.store")), .inMemory])
    func onlyMainAndGroupCanMirror(location: StoreLocation) {
        let configuration = DatabaseConfiguration(
            name: "Notes",
            schema: NoteSchema.self,
            location: location,
            cloudKit: CloudKitSync()
        )

        switch location {
        case .main, .group: #expect(configuration.canMirror)
        case .url, .inMemory: #expect(!configuration.canMirror)
        }
    }

    private func resolvedURL(for location: StoreLocation) -> URL {
        let configuration = DatabaseConfiguration(name: "Notes", schema: NoteSchema.self, location: location)

        return ModelContainerFactory.makeModelConfiguration(for: configuration, cloudKitEnabled: false).url
    }
}

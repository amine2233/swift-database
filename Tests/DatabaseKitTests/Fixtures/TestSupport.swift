@testable import DatabaseKit
import Foundation

final class DatabaseLoggerMock: DatabaseLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(DatabaseLogLevel, String)] = []

    var messages: [(DatabaseLogLevel, String)] {
        lock.withLock { storage }
    }

    func log(_ level: DatabaseLogLevel, _ message: String) {
        lock.withLock { storage.append((level, message)) }
    }
}

/// A directory that exists for one test and is removed with it.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "DatabaseKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func storeURL(named name: String = "Notes") -> URL {
        url.appending(path: "\(name).store")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

extension DatabaseConfiguration {
    static func inMemoryNotes() -> DatabaseConfiguration {
        DatabaseConfiguration(name: "Notes", schema: NoteSchema.self, location: .inMemory)
    }

    static func notes(at url: URL, schema: any DatabaseSchema.Type = NoteSchema.self) -> DatabaseConfiguration {
        DatabaseConfiguration(name: "Notes", schema: schema, location: .url(url))
    }
}

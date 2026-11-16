import os

public enum DatabaseLogLevel: Sendable {
    case debug
    case info
    case error
}

/// Every read, write and container lifecycle event is reported through this.
///
/// Sync makes a store impossible to reason about from the UI alone: a row can appear because CloudKit
/// imported it, or fail to appear because mirroring never started. The log is where the difference
/// becomes visible.
public protocol DatabaseLogger: Sendable {
    func log(_ level: DatabaseLogLevel, _ message: String)
}

public struct DatabaseLoggerDefault: DatabaseLogger {
    private let logger: Logger

    public init(subsystem: String = "DatabaseKit", category: String = "Database") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ level: DatabaseLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}

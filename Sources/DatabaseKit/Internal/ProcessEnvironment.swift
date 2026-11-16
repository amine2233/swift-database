import Foundation

enum ProcessEnvironment {
    /// Building a CloudKit-mirrored container inside a test host **aborts** the process rather than
    /// throwing, so mirroring is refused whenever this is true.
    static let isRunningTests: Bool = {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if processInfo.environment["XCTestSessionIdentifier"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        let executable = processInfo.arguments.first ?? ""
        return executable.hasSuffix(".xctest")
            || executable.contains("swiftpm-testing-helper")
            || executable.contains("swift-testing")
    }()
}

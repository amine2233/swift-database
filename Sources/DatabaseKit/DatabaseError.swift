/// Failures raised by DatabaseKit itself. Errors from SwiftData and Core Data are rethrown unchanged.
public enum DatabaseError: Error, Equatable, Sendable {
    /// The store could not be opened at all — see ``DatabaseDefault/ephemeral(schema:logger:)``.
    case storageUnavailable

    /// An update targeted a row that does not exist.
    case notFound(entity: String)
}

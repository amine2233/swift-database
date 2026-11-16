/// A store whose container can be replaced while the app runs.
///
/// Callers never hold on to a ``DatabaseActor``: they ask for it on every operation, so a container
/// rebuilt by ``setCloudKitEnabled(_:)`` is picked up without anyone having to be told.
public protocol Database: Sendable {
    /// Whether this store lives only as long as the process.
    ///
    /// True when the real store could not be opened and the app degraded to memory. Nothing written
    /// here survives a relaunch, so the UI has to say so rather than let the user believe their work
    /// is saved.
    nonisolated var isEphemeral: Bool { get }

    var isCloudKitEnabled: Bool { get async }

    /// The actor every query and mutation runs on. Throws ``DatabaseError/storageUnavailable`` when
    /// there is no store behind it.
    func modelActor() async throws -> DatabaseActor

    /// Rebuilds the container against the same file with mirroring on or off.
    ///
    /// A no-op for a store that cannot mirror — no ``DatabaseConfiguration/cloudKit``, an in-memory or
    /// file-URL location, or a test host, where a CloudKit container aborts the process.
    func setCloudKitEnabled(_ enabled: Bool) async throws
}

extension Database {
    /// A repository over `Entity`, bound to this store rather than to its current actor.
    public func repository<Entity: DatabaseEntity>(for _: Entity.Type) -> RepositoryDefault<Entity> {
        RepositoryDefault(database: self)
    }
}

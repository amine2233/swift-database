import Foundation
import SwiftData

/// Everything needed to open a store, independent of which process opens it.
///
/// ``location`` has no default on purpose: whether the file lives in the app's own container or in a
/// shared App Group decides which processes can ever see it, and moving it later is a migration of
/// its own. See ``StoreLocation``.
///
/// An app and its extensions build the **same** configuration — same ``name``, same
/// ``StoreLocation/group(_:)`` — so they open the same file. Never derive ``name`` from
/// `Bundle.main.bundleIdentifier`: an extension has its own, and would silently open a second store.
public struct DatabaseConfiguration: Sendable {
    public var name: String
    public var schema: any DatabaseSchema.Type
    public var location: StoreLocation
    /// `nil` for a store that never mirrors.
    public var cloudKit: CloudKitSync?
    /// `false` for a reader such as a widget, which must never write a store the app owns.
    public var allowsSave: Bool
    public var incompatibleStorePolicy: IncompatibleStorePolicy

    public init(
        name: String,
        schema: any DatabaseSchema.Type,
        location: StoreLocation,
        cloudKit: CloudKitSync? = nil,
        allowsSave: Bool = true,
        incompatibleStorePolicy: IncompatibleStorePolicy = .fail
    ) {
        self.name = name
        self.schema = schema
        self.location = location
        self.cloudKit = cloudKit
        self.allowsSave = allowsSave
        self.incompatibleStorePolicy = incompatibleStorePolicy
    }

    var canMirror: Bool {
        guard cloudKit != nil else { return false }

        return switch location {
        case .main, .group: true
        case .url, .inMemory: false
        }
    }

    var canRebuild: Bool {
        location != .inMemory
    }
}

/// Where the store's file lives — the one decision that fixes which processes can open it.
public enum StoreLocation: Sendable, Hashable {
    /// `Library/Application Support/<name>.store` inside **this process's own** container.
    ///
    /// Every extension has a container of its own, so a share, Safari or widget extension opening
    /// `.main` gets a different, empty file. Choose it for an app with no extension that reads or
    /// writes the data.
    case main
    /// `Library/Application Support/<name>.store` inside the App Group container `identifier`,
    /// shared by the app and every extension carrying the same App Groups entitlement.
    ///
    /// Choose it as soon as one extension needs the data — and from the first release if one ever
    /// might, since moving an existing `.main` store into a group means copying the file yourself.
    case group(_ identifier: String)
    /// A specific file. Never mirrored: a store addressed by path is a fixture or a repair copy.
    case url(URL)
    /// Lives as long as the container. Never mirrored, never rebuilt.
    case inMemory
}

/// Where a store mirrors to, once mirroring is on.
public struct CloudKitSync: Sendable, Hashable {
    public enum Container: Sendable, Hashable {
        /// The first iCloud container in the app's entitlements.
        case automatic
        case identifier(String)
    }

    public var container: Container

    /// Off by default: when sync is a paid feature, the entitlement is rarely known at launch, and a
    /// store opened mirroring would export for a lapsed subscriber before the check completes. Turn it
    /// on with ``Database/setCloudKitEnabled(_:)`` once it is.
    public var isEnabledAtLaunch: Bool

    public init(container: Container = .automatic, isEnabledAtLaunch: Bool = false) {
        self.container = container
        self.isEnabledAtLaunch = isEnabledAtLaunch
    }

    var database: ModelConfiguration.CloudKitDatabase {
        switch container {
        case .automatic: .automatic
        case let .identifier(identifier): .private(identifier)
        }
    }
}

/// What to do with a file whose schema version no migration plan stage recognises.
public enum IncompatibleStorePolicy: Sendable, Hashable {
    /// Throw, leaving the file untouched.
    case fail
    /// Delete the file and start empty. **Destroys data** — for caches and fixtures, never user content.
    case deleteAndRecreate
}

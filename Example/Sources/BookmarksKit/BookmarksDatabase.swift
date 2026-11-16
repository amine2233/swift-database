import DatabaseKit
import Foundation

/// The one configuration the app and both extensions open.
///
/// `.group` because the share and Safari extensions write bookmarks the app must see: with `.main`
/// each process would open its own, separate file. Must match the App Groups entitlement in
/// `Project.swift`.
public enum BookmarksDatabase {
    public static let appGroup = "group.com.example.databasekit.bookmarks"

    public static let configuration = DatabaseConfiguration(
        name: "Bookmarks",
        schema: BookmarkSchema.self,
        location: .group(appGroup)
    )

    /// One store per process. Never traps: a store that will not open degrades to memory and says so
    /// through `isEphemeral`.
    public static let shared: DatabaseDefault = {
        let logger = DatabaseLoggerDefault(subsystem: "com.example.databasekit.bookmarks", category: "Database")
        let database = DatabaseDefault.makeOrEphemeral(configuration: configuration, logger: logger)
        logger.log(.info, "Bookmarks store: \(database.storeURL.path)")

        return database
    }()

    public static var repository: RepositoryDefault<BookmarkEntity> {
        shared.repository(for: BookmarkEntity.self)
    }
}

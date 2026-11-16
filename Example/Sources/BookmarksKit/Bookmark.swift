import Foundation

public struct Bookmark: Identifiable, Sendable, Hashable {
    public enum Source: String, Sendable, Codable {
        case app
        case shareExtension
        case safariExtension
    }

    public var id: UUID
    public var title: String
    public var url: URL
    public var source: Source
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, url: URL, source: Source, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.url = url
        self.source = source
        self.createdAt = createdAt
    }
}

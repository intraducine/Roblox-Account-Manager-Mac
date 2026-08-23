import Foundation

public struct SavedPrivateServer: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let placeID: Int64
    public var link: String
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        placeID: Int64,
        link: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.placeID = placeID
        self.link = link
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public typealias PrivateServerRepository = JSONFileRepository<SavedPrivateServer>

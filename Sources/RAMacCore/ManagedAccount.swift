import Foundation

public struct ManagedAccount: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var userID: Int64
    public var username: String
    public var displayName: String
    public var alias: String
    public var group: String
    public var notes: String
    public var createdAt: Date
    public var lastUsed: Date?
    public var savedPlaceID: String
    public var savedServer: String
    public var avatarURLString: String?

    public init(
        id: UUID = UUID(),
        userID: Int64,
        username: String,
        displayName: String,
        alias: String = "",
        group: String = "Default",
        notes: String = "",
        createdAt: Date = Date(),
        lastUsed: Date? = nil,
        savedPlaceID: String = "",
        savedServer: String = "",
        avatarURLString: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.alias = alias
        self.group = group.isEmpty ? "Default" : group
        self.notes = notes
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.savedPlaceID = savedPlaceID
        self.savedServer = savedServer
        self.avatarURLString = avatarURLString
    }

    public var title: String {
        let cleanAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanAlias.isEmpty ? displayName : cleanAlias
    }

    public var avatarURL: URL? {
        avatarURLString.flatMap(URL.init(string:))
    }
}

public struct RobloxUser: Decodable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let displayName: String
}

struct RobloxThumbnailResponse: Decodable {
    struct Item: Decodable {
        let state: String
        let imageUrl: String?
    }
    let data: [Item]
}

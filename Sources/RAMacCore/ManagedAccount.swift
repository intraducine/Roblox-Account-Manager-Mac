import Foundation

public struct ManagedAccount: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var userID: Int64
    public var username: String
    public var displayName: String
    public var alias: String
    public var groups: [String]
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
        group: String? = nil,
        groups: [String] = [],
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
        self.groups = Self.normalizedGroups(group.map { [$0] } ?? groups)
        self.notes = notes
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.savedPlaceID = savedPlaceID
        self.savedServer = savedServer
        self.avatarURLString = Self.validatedAvatarURL(from: avatarURLString)?.absoluteString
    }

    public var title: String {
        let cleanAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanAlias.isEmpty ? displayName : cleanAlias
    }

    public var avatarURL: URL? {
        Self.validatedAvatarURL(from: avatarURLString)
    }

    public static func validatedAvatarURL(from value: String?) -> URL? {
        guard let value,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              host == "rbxcdn.com" || host.hasSuffix(".rbxcdn.com") else { return nil }
        return components.url
    }

    public func belongs(to group: String) -> Bool {
        groups.contains { $0.caseInsensitiveCompare(group) == .orderedSame }
    }

    public static func normalizedGroups(_ groups: [String]) -> [String] {
        var result: [String] = []
        for rawGroup in groups {
            let group = rawGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !group.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(group) == .orderedSame }) else { continue }
            result.append(group)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userID
        case username
        case displayName
        case alias
        case group
        case groups
        case notes
        case createdAt
        case lastUsed
        case savedPlaceID
        case savedServer
        case avatarURLString
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userID = try values.decode(Int64.self, forKey: .userID)
        username = try values.decode(String.self, forKey: .username)
        displayName = try values.decode(String.self, forKey: .displayName)
        alias = try values.decodeIfPresent(String.self, forKey: .alias) ?? ""
        if let decodedGroups = try values.decodeIfPresent([String].self, forKey: .groups) {
            groups = Self.normalizedGroups(decodedGroups)
        } else if let legacyGroup = try values.decodeIfPresent(String.self, forKey: .group) {
            groups = Self.normalizedGroups([legacyGroup])
        } else {
            groups = []
        }
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsed = try values.decodeIfPresent(Date.self, forKey: .lastUsed)
        savedPlaceID = try values.decodeIfPresent(String.self, forKey: .savedPlaceID) ?? ""
        savedServer = try values.decodeIfPresent(String.self, forKey: .savedServer) ?? ""
        avatarURLString = Self.validatedAvatarURL(
            from: try values.decodeIfPresent(String.self, forKey: .avatarURLString)
        )?.absoluteString
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userID, forKey: .userID)
        try values.encode(username, forKey: .username)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(alias, forKey: .alias)
        try values.encode(Self.normalizedGroups(groups), forKey: .groups)
        try values.encode(notes, forKey: .notes)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(lastUsed, forKey: .lastUsed)
        try values.encode(savedPlaceID, forKey: .savedPlaceID)
        try values.encode(savedServer, forKey: .savedServer)
        try values.encodeIfPresent(avatarURLString, forKey: .avatarURLString)
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

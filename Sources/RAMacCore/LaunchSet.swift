import Foundation

public enum ServerStrategy: Codable, Equatable, Sendable {
    case robloxChooses
    case browseBeforeLaunch
    case joinPlayer
    case privateServerLink(String)

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case robloxChooses, browseBeforeLaunch, joinPlayer, privateServerLink }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .robloxChooses: self = .robloxChooses
        case .browseBeforeLaunch: self = .browseBeforeLaunch
        case .joinPlayer: self = .joinPlayer
        case .privateServerLink: self = .privateServerLink(try values.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .robloxChooses:
            try values.encode(Kind.robloxChooses, forKey: .kind)
        case .browseBeforeLaunch:
            try values.encode(Kind.browseBeforeLaunch, forKey: .kind)
        case .joinPlayer:
            try values.encode(Kind.joinPlayer, forKey: .kind)
        case .privateServerLink(let value):
            try values.encode(Kind.privateServerLink, forKey: .kind)
            try values.encode(value, forKey: .value)
        }
    }

    public var title: String {
        switch self {
        case .robloxChooses: return "Roblox chooses"
        case .browseBeforeLaunch: return "Browse before launch"
        case .joinPlayer: return "Join a player"
        case .privateServerLink: return "Private server link"
        }
    }
}

public struct LaunchSet: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var accountIDs: [UUID]
    public var groupNames: [String]
    public var placeID: Int64
    public var experienceName: String?
    public var serverStrategy: ServerStrategy
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        accountIDs: [UUID] = [],
        groupNames: [String] = [],
        placeID: Int64,
        experienceName: String? = nil,
        serverStrategy: ServerStrategy = .robloxChooses,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.accountIDs = Array(Set(accountIDs))
        self.groupNames = ManagedAccount.normalizedGroups(groupNames)
        self.placeID = placeID
        self.experienceName = experienceName
        self.serverStrategy = serverStrategy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public final class LaunchSetRepository: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(dataDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = (dataDirectory ?? AccountRepository.defaultDataDirectory(fileManager: fileManager))
            .appendingPathComponent("LaunchSets.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [LaunchSet] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([LaunchSet].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ sets: [LaunchSet]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(sets).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

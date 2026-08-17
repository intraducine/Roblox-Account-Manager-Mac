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
    public var windowArrangement: WindowArrangementPolicy
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
        windowArrangement: WindowArrangementPolicy = .savedPlacements,
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
        self.windowArrangement = windowArrangement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func setGroupSelection(
        _ group: String,
        selected: Bool,
        accounts: [ManagedAccount]
    ) {
        guard let normalizedGroup = ManagedAccount.normalizedGroups([group]).first else { return }

        let members = accounts.filter { $0.belongs(to: normalizedGroup) }
        if selected {
            groupNames = ManagedAccount.normalizedGroups(groupNames + [normalizedGroup])
            var selectedIDs = Set(accountIDs)
            for account in members where selectedIDs.insert(account.id).inserted {
                accountIDs.append(account.id)
            }
            return
        }

        groupNames.removeAll { $0.caseInsensitiveCompare(normalizedGroup) == .orderedSame }
        let remainingGroupMemberIDs = Set(accounts.compactMap { account in
            groupNames.contains(where: { account.belongs(to: $0) }) ? account.id : nil
        })
        let removedGroupMemberIDs = Set(members.map(\.id)).subtracting(remainingGroupMemberIDs)
        accountIDs.removeAll { removedGroupMemberIDs.contains($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, accountIDs, groupNames, placeID, experienceName, serverStrategy
        case windowArrangement, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        accountIDs = Array(Set(try values.decodeIfPresent([UUID].self, forKey: .accountIDs) ?? []))
        groupNames = ManagedAccount.normalizedGroups(
            try values.decodeIfPresent([String].self, forKey: .groupNames) ?? []
        )
        placeID = try values.decode(Int64.self, forKey: .placeID)
        experienceName = try values.decodeIfPresent(String.self, forKey: .experienceName)
        serverStrategy = try values.decodeIfPresent(ServerStrategy.self, forKey: .serverStrategy) ?? .robloxChooses
        windowArrangement = try values.decodeIfPresent(
            WindowArrangementPolicy.self,
            forKey: .windowArrangement
        ) ?? .savedPlacements
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(accountIDs, forKey: .accountIDs)
        try values.encode(groupNames, forKey: .groupNames)
        try values.encode(placeID, forKey: .placeID)
        try values.encodeIfPresent(experienceName, forKey: .experienceName)
        try values.encode(serverStrategy, forKey: .serverStrategy)
        try values.encode(windowArrangement, forKey: .windowArrangement)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
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

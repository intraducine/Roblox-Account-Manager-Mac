import Foundation

public struct MetadataArchive: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let exportedAt: Date
    public var accounts: [ManagedAccount]
    public var groups: [String]
    public var experiences: [ExperienceRecord]
    public var launchSets: [LaunchSet]

    public init(
        formatVersion: Int = 1,
        exportedAt: Date = Date(),
        accounts: [ManagedAccount],
        groups: [String],
        experiences: [ExperienceRecord],
        launchSets: [LaunchSet]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.accounts = accounts
        self.groups = groups
        self.experiences = experiences
        self.launchSets = launchSets
    }
}

public struct MetadataImportResult: Equatable, Sendable {
    public let accounts: [ManagedAccount]
    public let groups: [String]
    public let experiences: [ExperienceRecord]
    public let launchSets: [LaunchSet]
    public let importedAccountCount: Int
}

public struct MetadataArchiveService: Sendable {
    public static let maximumArchiveBytes = 10 * 1024 * 1024
    private static let maximumAccounts = 10_000
    private static let maximumGroups = 5_000
    private static let maximumExperiences = 50_000
    private static let maximumLaunchSets = 10_000
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func exportData(
        accounts: [ManagedAccount],
        groups: [String],
        experiences: [ExperienceRecord],
        launchSets: [LaunchSet],
        includePrivateLinks: Bool = false
    ) throws -> Data {
        let safeAccounts = accounts.map { account -> ManagedAccount in
            var safe = account
            safe.notes = ""
            if !includePrivateLinks,
               RobloxLaunchURLBuilder.privateLinkCode(from: safe.savedServer) != nil
                || RobloxLaunchURLBuilder.privateShareCode(from: safe.savedServer) != nil {
                safe.savedServer = ""
            }
            return safe
        }
        let safeSets = launchSets.map { set -> LaunchSet in
            guard !includePrivateLinks, case .privateServerLink = set.serverStrategy else { return set }
            var safe = set
            safe.serverStrategy = .robloxChooses
            return safe
        }
        return try encoder.encode(MetadataArchive(
            accounts: safeAccounts,
            groups: ManagedAccount.normalizedGroups(groups),
            experiences: experiences,
            launchSets: safeSets
        ))
    }

    public func importData(
        _ data: Data,
        existingAccounts: [ManagedAccount],
        existingGroups: [String],
        existingExperiences: [ExperienceRecord],
        existingLaunchSets: [LaunchSet]
    ) throws -> MetadataImportResult {
        guard data.count <= Self.maximumArchiveBytes else { throw ArchiveError.tooLarge }
        let archive = try decoder.decode(MetadataArchive.self, from: data)
        guard archive.formatVersion == 1 else { throw ArchiveError.unsupportedVersion }
        guard archive.accounts.count <= Self.maximumAccounts,
              archive.groups.count <= Self.maximumGroups,
              archive.experiences.count <= Self.maximumExperiences,
              archive.launchSets.count <= Self.maximumLaunchSets else {
            throw ArchiveError.tooManyRecords
        }
        var accounts = existingAccounts
        var importedCount = 0
        var accountIDMap: [UUID: UUID] = [:]
        for imported in archive.accounts {
            if let index = accounts.firstIndex(where: { $0.userID == imported.userID }) {
                let id = accounts[index].id
                let createdAt = accounts[index].createdAt
                let localNotes = accounts[index].notes
                var merged = imported
                merged.id = id
                merged.createdAt = createdAt
                merged.notes = localNotes
                accounts[index] = merged
                accountIDMap[imported.id] = id
            } else {
                var newAccount = imported
                if accounts.contains(where: { $0.id == imported.id }) {
                    newAccount.id = UUID()
                }
                accounts.append(newAccount)
                accountIDMap[imported.id] = newAccount.id
                importedCount += 1
            }
        }

        var experiences = Dictionary(existingExperiences.map { ($0.placeID, $0) }) { current, _ in current }
        for imported in archive.experiences {
            if let current = experiences[imported.placeID] {
                var merged = current.lastLaunchedAt >= imported.lastLaunchedAt ? current : imported
                merged.launchCount = max(current.launchCount, imported.launchCount)
                merged.isFavorite = current.isFavorite || imported.isFavorite
                experiences[imported.placeID] = merged
            } else {
                experiences[imported.placeID] = imported
            }
        }

        var sets = Dictionary(existingLaunchSets.map { ($0.id, $0) }) { current, _ in current }
        for imported in archive.launchSets {
            var mapped = imported
            mapped.accountIDs = imported.accountIDs.compactMap { accountIDMap[$0] }
            sets[imported.id] = mapped
        }
        return MetadataImportResult(
            accounts: accounts,
            groups: ManagedAccount.normalizedGroups(existingGroups + archive.groups + accounts.flatMap(\.groups)),
            experiences: experiences.values.sorted { $0.lastLaunchedAt > $1.lastLaunchedAt },
            launchSets: sets.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            importedAccountCount: importedCount
        )
    }

    public enum ArchiveError: LocalizedError {
        case unsupportedVersion
        case tooLarge
        case tooManyRecords

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "This backup was made by an unsupported app version."
            case .tooLarge:
                return "This backup is larger than the 10 MB safety limit."
            case .tooManyRecords:
                return "This backup contains too many records to import safely."
            }
        }
    }
}

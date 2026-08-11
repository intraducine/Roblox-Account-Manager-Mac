import Foundation

public enum ActiveLaunchTargetKind: String, Codable, Equatable, Sendable {
    case automatic
    case publicJob
    case verifiedPublicJob
    case privateServer
}

public struct ActiveLaunchTargetRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { accountID }
    public let accountID: UUID
    public let processIdentifier: Int32
    public let placeID: Int64
    public let targetKind: ActiveLaunchTargetKind
    public let jobID: String?
    public let privateServerReference: String?
    public let launchedAt: Date

    public init(
        accountID: UUID,
        processIdentifier: Int32,
        placeID: Int64,
        targetKind: ActiveLaunchTargetKind,
        jobID: String? = nil,
        privateServerReference: String? = nil,
        launchedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.processIdentifier = processIdentifier
        self.placeID = placeID
        self.targetKind = targetKind
        self.jobID = jobID
        self.privateServerReference = privateServerReference
        self.launchedAt = launchedAt
    }
}

public final class ActiveLaunchTargetRepository: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(dataDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        fileURL = (dataDirectory ?? AccountRepository.defaultDataDirectory(fileManager: fileManager))
            .appendingPathComponent("ActiveLaunches.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [ActiveLaunchTargetRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([ActiveLaunchTargetRecord].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ records: [ActiveLaunchTargetRecord]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

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

public final class PrivateServerRepository: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(dataDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = (dataDirectory ?? AccountRepository.defaultDataDirectory(fileManager: fileManager))
            .appendingPathComponent("PrivateServers.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [SavedPrivateServer] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([SavedPrivateServer].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ servers: [SavedPrivateServer]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(servers).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

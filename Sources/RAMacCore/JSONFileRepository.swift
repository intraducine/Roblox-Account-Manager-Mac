import Foundation

public final class JSONFileRepository<Record: Codable & Sendable>: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(
        fileName: String,
        dataDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = (dataDirectory ?? AccountRepository.defaultDataDirectory(fileManager: fileManager))
            .appendingPathComponent(fileName)
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [Record] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([Record].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ records: [Record]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

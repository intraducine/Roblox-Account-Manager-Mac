import Foundation

public struct JSONFileRepositoryLoadResult<Record: Sendable>: Sendable {
    public let records: [Record]
    public let recoveredFromBackup: Bool
}

public final class JSONFileRepository<Record: Codable & Sendable>: @unchecked Sendable {
    private let fileURL: URL
    private let backupURL: URL
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
        let fileExtension = self.fileURL.pathExtension
        let backupName = self.fileURL.deletingPathExtension().lastPathComponent + ".backup"
        self.backupURL = self.fileURL.deletingLastPathComponent()
            .appendingPathComponent(backupName)
            .appendingPathExtension(fileExtension)
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [Record] {
        try loadWithRecovery().records
    }

    public func loadWithRecovery() throws -> JSONFileRepositoryLoadResult<Record> {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return JSONFileRepositoryLoadResult(records: [], recoveredFromBackup: false)
        }
        do {
            return JSONFileRepositoryLoadResult(
                records: try decodeRecords(at: fileURL),
                recoveredFromBackup: false
            )
        } catch {
            let primaryError = error
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw RepositoryError.unreadable(
                    fileName: fileURL.lastPathComponent,
                    reason: primaryError.localizedDescription
                )
            }
            do {
                let backupData = try Data(contentsOf: backupURL)
                let records = try decoder.decode([Record].self, from: backupData)
                try? backupData.write(to: fileURL, options: [.atomic, .completeFileProtection])
                return JSONFileRepositoryLoadResult(records: records, recoveredFromBackup: true)
            } catch {
                throw RepositoryError.unreadable(
                    fileName: fileURL.lastPathComponent,
                    reason: "The current file and its backup could not be read."
                )
            }
        }
    }

    public func save(_ records: [Record]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path),
           let currentData = try? Data(contentsOf: fileURL),
           (try? decoder.decode([Record].self, from: currentData)) != nil {
            try currentData.write(to: backupURL, options: [.atomic, .completeFileProtection])
        }
        try encoder.encode(records).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func decodeRecords(at url: URL) throws -> [Record] {
        try decoder.decode([Record].self, from: Data(contentsOf: url))
    }

    public enum RepositoryError: LocalizedError {
        case unreadable(fileName: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let fileName, let reason):
                return "\(fileName) is damaged and no valid backup is available. \(reason) The files were kept unchanged."
            }
        }
    }
}

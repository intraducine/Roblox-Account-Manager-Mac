import Foundation

public final class AccountRepository: @unchecked Sendable {
    public let dataDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        dataDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.dataDirectory = dataDirectory ?? Self.defaultDataDirectory(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        decoder.dateDecodingStrategy = .deferredToDate
    }

    public func load() throws -> [ManagedAccount] {
        let file = dataDirectory.appendingPathComponent("Accounts.json")
        guard fileManager.fileExists(atPath: file.path) else { return [] }
        return try decoder.decode([ManagedAccount].self, from: Data(contentsOf: file))
    }

    public func save(_ accounts: [ManagedAccount]) throws {
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let file = dataDirectory.appendingPathComponent("Accounts.json")
        let backup = dataDirectory.appendingPathComponent("Accounts.backup.json")

        if fileManager.fileExists(atPath: file.path) {
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: file, to: backup)
        }

        try encoder.encode(accounts).write(to: file, options: [.atomic, .completeFileProtection])
    }

    public func loadGroups() throws -> [String] {
        let file = dataDirectory.appendingPathComponent("Groups.json")
        guard fileManager.fileExists(atPath: file.path) else { return [] }
        return ManagedAccount.normalizedGroups(
            try decoder.decode([String].self, from: Data(contentsOf: file))
        )
    }

    public func saveGroups(_ groups: [String]) throws {
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let file = dataDirectory.appendingPathComponent("Groups.json")
        try encoder.encode(ManagedAccount.normalizedGroups(groups)).write(
            to: file,
            options: [.atomic, .completeFileProtection]
        )
    }

    public static func defaultDataDirectory(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Roblox Account Manager", isDirectory: true)
    }
}

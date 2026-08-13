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
        let accounts = try decoder.decode([ManagedAccount].self, from: Data(contentsOf: file))
        guard Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.map(\.userID)).count == accounts.count else {
            throw RepositoryError.duplicateAccount
        }
        try scrubLegacyNotesFromBackup()
        return accounts
    }

    public func save(_ accounts: [ManagedAccount]) throws {
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let file = dataDirectory.appendingPathComponent("Accounts.json")
        let backup = dataDirectory.appendingPathComponent("Accounts.backup.json")

        if fileManager.fileExists(atPath: file.path) {
            try? fileManager.removeItem(at: backup)
            if let previousAccounts = try? decoder.decode(
                [ManagedAccount].self,
                from: Data(contentsOf: file)
            ) {
                try encoder.encode(previousAccounts).write(
                    to: backup,
                    options: [.atomic, .completeFileProtection]
                )
            }
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

    private func scrubLegacyNotesFromBackup() throws {
        let backup = dataDirectory.appendingPathComponent("Accounts.backup.json")
        guard fileManager.fileExists(atPath: backup.path) else { return }
        do {
            let data = try Data(contentsOf: backup)
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            guard rows?.contains(where: { $0["notes"] != nil }) == true else { return }
            let accounts = try decoder.decode(
                [ManagedAccount].self,
                from: data
            )
            try encoder.encode(accounts).write(
                to: backup,
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            try fileManager.removeItem(at: backup)
        }
    }

    public enum RepositoryError: LocalizedError {
        case duplicateAccount

        public var errorDescription: String? {
            "Accounts.json contains a duplicate account. Restore Accounts.backup.json or remove the duplicate record."
        }
    }
}

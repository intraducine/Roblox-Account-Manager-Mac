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
        try loadWithRecovery().records
    }

    public func loadWithRecovery(
        migrateLegacyNote: ((ManagedAccount) throws -> Void)? = nil
    ) throws -> JSONFileRepositoryLoadResult<ManagedAccount> {
        let file = dataDirectory.appendingPathComponent("Accounts.json")
        let backup = dataDirectory.appendingPathComponent("Accounts.backup.json")
        guard fileManager.fileExists(atPath: file.path) || fileManager.fileExists(atPath: backup.path) else {
            return JSONFileRepositoryLoadResult(records: [], recoveredFromBackup: false)
        }
        let accounts: [ManagedAccount]
        do {
            accounts = try readAccounts(at: file)
        } catch {
            guard let recovered = try? readAccounts(at: backup) else { throw error }
            for account in recovered where !account.notes.isEmpty {
                guard let migrateLegacyNote else { throw RepositoryError.recoveryRequired }
                try migrateLegacyNote(account)
            }
            try encoder.encode(recovered).write(to: file, options: [.atomic, .completeFileProtection])
            try scrubLegacyNotesFromBackup()
            return JSONFileRepositoryLoadResult(records: recovered, recoveredFromBackup: true)
        }
        try scrubLegacyNotesFromBackup()
        return JSONFileRepositoryLoadResult(records: accounts, recoveredFromBackup: false)
    }

    private func readAccounts(at file: URL) throws -> [ManagedAccount] {
        let accounts = try decoder.decode([ManagedAccount].self, from: Data(contentsOf: file))
        guard Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.map(\.userID)).count == accounts.count else {
            throw RepositoryError.duplicateAccount
        }
        return accounts
    }

    public func save(_ accounts: [ManagedAccount]) throws {
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let file = dataDirectory.appendingPathComponent("Accounts.json")
        let backup = dataDirectory.appendingPathComponent("Accounts.backup.json")

        if fileManager.fileExists(atPath: file.path) {
            let previousAccounts = try readAccounts(at: file)
            try encoder.encode(previousAccounts).write(to: backup, options: [.atomic, .completeFileProtection])
        } else if fileManager.fileExists(atPath: backup.path) {
            throw RepositoryError.recoveryRequired
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
        guard let data = try? Data(contentsOf: backup),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.contains(where: { $0["notes"] != nil }),
              let accounts = try? readAccounts(at: backup) else { return }
        try encoder.encode(accounts).write(to: backup, options: [.atomic, .completeFileProtection])
    }

    public enum RepositoryError: LocalizedError {
        case duplicateAccount
        case recoveryRequired

        public var errorDescription: String? {
            switch self {
            case .duplicateAccount:
                return "Accounts.json contains a duplicate account. Restore Accounts.backup.json or remove the duplicate record."
            case .recoveryRequired:
                return "Reload the account backup before saving changes."
            }
        }
    }
}

import Foundation
import Security

public protocol SecretVault: Sendable {
    func save(_ secret: String, for accountID: UUID) throws
    func read(for accountID: UUID) throws -> String?
    func delete(for accountID: UUID) throws
}

public enum SecretVaultError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain returned error \(status)."
        case .invalidData:
            return "The saved session is not valid text."
        }
    }
}

public final class KeychainVault: SecretVault, @unchecked Sendable {
    private struct SessionContainer: Codable {
        var version = 1
        var sessions: [String: String]
    }

    private static let containerAccount = "sessions-v1"
    private let service: String
    private let lock = NSLock()
    private var cachedSessions: [String: String]?

    public init(service: String = "com.intraducine.RobloxAccountManager.session") {
        self.service = service
    }

    public func save(_ secret: String, for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var sessions = try loadSessionsLocked()
        sessions[accountID.uuidString] = secret
        try saveSessionsLocked(sessions)
    }

    public func read(for accountID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        var sessions = try loadSessionsLocked()
        let account = accountID.uuidString
        if let secret = sessions[account] { return secret }

        guard let legacySecret = try readItemLocked(account: account) else { return nil }
        sessions[account] = legacySecret
        try saveSessionsLocked(sessions)
        try deleteItemLocked(account: account)
        return legacySecret
    }

    public func delete(for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var sessions = try loadSessionsLocked()
        sessions[accountID.uuidString] = nil
        if sessions.isEmpty {
            try deleteItemLocked(account: Self.containerAccount)
            cachedSessions = [:]
        } else {
            try saveSessionsLocked(sessions)
        }
        try deleteItemLocked(account: accountID.uuidString)
    }

    private func loadSessionsLocked() throws -> [String: String] {
        if let cachedSessions { return cachedSessions }
        guard let data = try readDataLocked(account: Self.containerAccount) else {
            cachedSessions = [:]
            return [:]
        }
        guard let container = try? JSONDecoder().decode(SessionContainer.self, from: data),
              container.version == 1 else {
            throw SecretVaultError.invalidData
        }
        cachedSessions = container.sessions
        return container.sessions
    }

    private func saveSessionsLocked(_ sessions: [String: String]) throws {
        let data = try JSONEncoder().encode(SessionContainer(sessions: sessions))
        let base = itemQuery(account: Self.containerAccount)
        let status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            cachedSessions = sessions
            return
        }
        guard status == errSecItemNotFound else {
            throw SecretVaultError.unexpectedStatus(status)
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretVaultError.unexpectedStatus(addStatus)
        }
        cachedSessions = sessions
    }

    private func readItemLocked(account: String) throws -> String? {
        guard let data = try readDataLocked(account: account) else { return nil }
        guard let secret = String(data: data, encoding: .utf8) else {
            throw SecretVaultError.invalidData
        }
        return secret
    }

    private func readDataLocked(account: String) throws -> Data? {
        var query = itemQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretVaultError.unexpectedStatus(status)
        }
        guard let data = result as? Data else { throw SecretVaultError.invalidData }
        return data
    }

    private func deleteItemLocked(account: String) throws {
        let status = SecItemDelete(itemQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretVaultError.unexpectedStatus(status)
        }
    }

    private func itemQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

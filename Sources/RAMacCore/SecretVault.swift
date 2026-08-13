import Foundation
import Security

public protocol SecretVault: Sendable {
    func save(_ secret: String, for accountID: UUID) throws
    func read(for accountID: UUID) throws -> String?
    func delete(for accountID: UUID) throws
}

public protocol ProfileNoteVault: Sendable {
    func saveNote(_ note: String, for accountID: UUID) throws
    func readNote(for accountID: UUID) throws -> String?
    func deleteNote(for accountID: UUID) throws
}

public enum ProfileNoteVaultError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "macOS Keychain could not protect the profile note. \(detail) (\(status))"
        case .invalidData:
            return "The encrypted profile note could not be read from macOS Keychain."
        }
    }
}

public enum SecretVaultError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            switch status {
            case errSecAuthFailed:
                return "macOS blocked access to the saved Roblox sign-ins. Close every other copy of this app, open the installed app again, and retry."
            case errSecInteractionNotAllowed:
                return "macOS could not ask for Keychain access. Unlock your Mac, open the installed app, and retry."
            case errSecUserCanceled:
                return "Keychain access was canceled. Retry and approve the macOS request if it appears."
            default:
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
                return "macOS Keychain could not save the Roblox sign-in. \(detail) (\(status))"
            }
        case .invalidData:
            return "The saved Roblox sign-in could not be read. Sign in to this account again."
        }
    }
}

public final class KeychainVault: SecretVault, @unchecked Sendable {
    private struct SessionContainer: Codable {
        var version = 2
        var sessions: [String: String]
    }

    private static let containerAccount = "sessions-v2"
    private static let legacyContainerAccount = "sessions-v1"
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

        let legacySecret: String?
        do {
            legacySecret = try readItemLocked(account: account)
        } catch where Self.isLegacyAccessFailure(error) {
            return nil
        }
        guard let legacySecret else { return nil }
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
        do {
            try deleteItemLocked(account: accountID.uuidString)
        } catch where Self.isLegacyAccessFailure(error) {
            // An older ad hoc build can own this obsolete item. The current
            // session is already removed from the active container.
        }
    }

    private func loadSessionsLocked() throws -> [String: String] {
        if let cachedSessions { return cachedSessions }
        if let data = try readDataLocked(account: Self.containerAccount) {
            guard let container = try? JSONDecoder().decode(SessionContainer.self, from: data),
                  container.version == 2 else {
                throw SecretVaultError.invalidData
            }
            cachedSessions = container.sessions
            return container.sessions
        }

        do {
            guard let legacyData = try readDataLocked(account: Self.legacyContainerAccount) else {
                cachedSessions = [:]
                return [:]
            }
            guard let legacy = try? JSONDecoder().decode(SessionContainer.self, from: legacyData),
                  legacy.version == 1 else {
                throw SecretVaultError.invalidData
            }
            try saveSessionsLocked(legacy.sessions)
            try? deleteItemLocked(account: Self.legacyContainerAccount)
            return legacy.sessions
        } catch where Self.isLegacyAccessFailure(error) {
            // Ad hoc signatures change after a rebuild. macOS can reject the
            // old item before it can show an approval prompt. Start a fresh,
            // versioned container so adding an account still works. Existing
            // account metadata remains and can be signed in again once.
            cachedSessions = [:]
            return [:]
        }
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

    private static func isLegacyAccessFailure(_ error: Error) -> Bool {
        guard let vaultError = error as? SecretVaultError else { return false }
        guard case .unexpectedStatus(let status) = vaultError else { return false }
        return status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecUserCanceled
    }
}

public final class KeychainProfileNoteVault: ProfileNoteVault, @unchecked Sendable {
    private struct NoteContainer: Codable {
        let version: Int
        var notes: [String: String]

        init(notes: [String: String]) {
            version = 1
            self.notes = notes
        }
    }

    private static let containerAccount = "notes-v1"
    private let service: String
    private let lock = NSLock()
    private var cachedNotes: [String: String]?

    public init(service: String = "com.intraducine.RobloxAccountManager.profile-notes") {
        self.service = service
    }

    public func saveNote(_ note: String, for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var notes = try loadNotesLocked()
        notes[accountID.uuidString] = note
        try saveNotesLocked(notes)
    }

    public func readNote(for accountID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try loadNotesLocked()[accountID.uuidString]
    }

    public func deleteNote(for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var notes = try loadNotesLocked()
        notes[accountID.uuidString] = nil
        if notes.isEmpty {
            let status = SecItemDelete(itemQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw ProfileNoteVaultError.unexpectedStatus(status)
            }
            cachedNotes = [:]
        } else {
            try saveNotesLocked(notes)
        }
    }

    private func loadNotesLocked() throws -> [String: String] {
        if let cachedNotes { return cachedNotes }
        var query = itemQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            cachedNotes = [:]
            return [:]
        }
        guard status == errSecSuccess else {
            throw ProfileNoteVaultError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let container = try? JSONDecoder().decode(NoteContainer.self, from: data),
              container.version == 1 else {
            throw ProfileNoteVaultError.invalidData
        }
        cachedNotes = container.notes
        return container.notes
    }

    private func saveNotesLocked(_ notes: [String: String]) throws {
        let data = try JSONEncoder().encode(NoteContainer(notes: notes))
        let base = itemQuery()
        let status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            cachedNotes = notes
            return
        }
        guard status == errSecItemNotFound else {
            throw ProfileNoteVaultError.unexpectedStatus(status)
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ProfileNoteVaultError.unexpectedStatus(addStatus)
        }
        cachedNotes = notes
    }

    private func itemQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.containerAccount
        ]
    }
}

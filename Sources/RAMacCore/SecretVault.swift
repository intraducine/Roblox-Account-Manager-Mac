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

public struct KeychainVault: SecretVault {
    private let service: String

    public init(service: String = "com.intraducine.RobloxAccountManager.session") {
        self.service = service
    }

    public func save(_ secret: String, for accountID: UUID) throws {
        let account = accountID.uuidString
        let encoded = Data(secret.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: encoded] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretVaultError.unexpectedStatus(updateStatus)
        }

        var add = base
        add[kSecValueData as String] = encoded
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretVaultError.unexpectedStatus(addStatus)
        }
    }

    public func read(for accountID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretVaultError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretVaultError.invalidData
        }
        return secret
    }

    public func delete(for accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretVaultError.unexpectedStatus(status)
        }
    }
}

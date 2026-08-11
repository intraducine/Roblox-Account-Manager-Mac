import Foundation
import Security
import XCTest
@testable import RAMacCore

final class SecretVaultTests: XCTestCase {
    func testKeychainRoundTrip() throws {
        let service = "com.intraducine.RobloxAccountManager.tests.\(UUID().uuidString)"
        let accountID = UUID()
        let vault = KeychainVault(service: service)
        defer { deleteAll(service: service) }

        try vault.save("temporary-test-session", for: accountID)
        XCTAssertEqual(try vault.read(for: accountID), "temporary-test-session")
        try vault.delete(for: accountID)
        XCTAssertNil(try vault.read(for: accountID))
    }

    func testSeveralAccountsUseOneKeychainItem() throws {
        let service = "com.intraducine.RobloxAccountManager.tests.\(UUID().uuidString)"
        let accountIDs = [UUID(), UUID(), UUID()]
        let vault = KeychainVault(service: service)
        defer { deleteAll(service: service) }

        for (index, accountID) in accountIDs.enumerated() {
            try vault.save("session-\(index)", for: accountID)
        }

        XCTAssertEqual(try keychainAccounts(service: service), ["sessions-v1"])
        for (index, accountID) in accountIDs.enumerated() {
            XCTAssertEqual(try vault.read(for: accountID), "session-\(index)")
        }

        try vault.delete(for: accountIDs[1])
        XCTAssertNil(try vault.read(for: accountIDs[1]))
        XCTAssertEqual(try vault.read(for: accountIDs[0]), "session-0")
        XCTAssertEqual(try vault.read(for: accountIDs[2]), "session-2")
        XCTAssertEqual(try keychainAccounts(service: service), ["sessions-v1"])
    }

    func testLegacyPerAccountItemMigratesIntoTheContainer() throws {
        let service = "com.intraducine.RobloxAccountManager.tests.\(UUID().uuidString)"
        let accountID = UUID()
        let vault = KeychainVault(service: service)
        defer { deleteAll(service: service) }
        let addStatus = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecValueData as String: Data("legacy-session".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ] as CFDictionary, nil)
        XCTAssertEqual(addStatus, errSecSuccess)

        XCTAssertEqual(try vault.read(for: accountID), "legacy-session")
        XCTAssertEqual(try keychainAccounts(service: service), ["sessions-v1"])
    }

    private func keychainAccounts(service: String) throws -> [String] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecretVaultError.unexpectedStatus(status) }
        let rows = result as? [[String: Any]] ?? []
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func deleteAll(service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)
    }
}

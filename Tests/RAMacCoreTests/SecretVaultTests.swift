import Foundation
import XCTest
@testable import RAMacCore

final class SecretVaultTests: XCTestCase {
    func testKeychainRoundTrip() throws {
        let accountID = UUID()
        let vault = KeychainVault(service: "com.intraducine.RobloxAccountManager.tests.\(UUID().uuidString)")
        defer { try? vault.delete(for: accountID) }

        try vault.save("temporary-test-session", for: accountID)
        XCTAssertEqual(try vault.read(for: accountID), "temporary-test-session")
        try vault.delete(for: accountID)
        XCTAssertNil(try vault.read(for: accountID))
    }
}

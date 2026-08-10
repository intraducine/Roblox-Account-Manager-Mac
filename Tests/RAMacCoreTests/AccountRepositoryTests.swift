import Foundation
import XCTest
@testable import RAMacCore

final class AccountRepositoryTests: XCTestCase {
    func testRoundTripAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let first = ManagedAccount(
            userID: 42,
            username: "builder",
            displayName: "Builder",
            alias: "Main",
            group: "Primary"
        )
        try repository.save([first])
        XCTAssertEqual(try repository.load(), [first])

        var changed = first
        changed.alias = "Updated"
        try repository.save([changed])
        XCTAssertEqual(try repository.load(), [changed])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Accounts.backup.json").path
        ))
    }
}

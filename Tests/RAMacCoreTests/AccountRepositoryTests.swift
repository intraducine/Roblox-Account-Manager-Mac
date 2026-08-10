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

    func testLoadsLegacySingleGroupAndSavesMultipleGroups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(
            userID: 7,
            username: "legacy",
            displayName: "Legacy",
            groups: ["First", "Second"]
        )
        try repository.save([account])

        let file = directory.appendingPathComponent("Accounts.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]]
        )
        object[0]["groups"] = nil
        object[0]["group"] = "Legacy Group"
        try JSONSerialization.data(withJSONObject: object).write(to: file)

        let migrated = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(migrated.groups, ["Legacy Group"])

        migrated.groups.forEach { XCTAssertTrue(migrated.belongs(to: $0)) }
        try repository.saveGroups(["Second", "First", "first"])
        XCTAssertEqual(try repository.loadGroups(), ["First", "Second"])
    }
}

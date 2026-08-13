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

    func testProfileNotesAreNotWrittenToAccountMetadataOrBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(
            userID: 17,
            username: "private-notes",
            displayName: "Private Notes",
            notes: "This note must stay encrypted"
        )

        try repository.save([account])
        var changed = account
        changed.alias = "Updated"
        try repository.save([changed])

        let metadata = String(decoding: try Data(
            contentsOf: directory.appendingPathComponent("Accounts.json")
        ), as: UTF8.self)
        let backup = String(decoding: try Data(
            contentsOf: directory.appendingPathComponent("Accounts.backup.json")
        ), as: UTF8.self)
        XCTAssertFalse(metadata.contains(account.notes))
        XCTAssertFalse(backup.contains(account.notes))
    }

    func testLoadScrubsAPlainTextNoteLeftOnlyInTheOldBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 18, username: "backup", displayName: "Backup")
        try repository.save([account])

        var backupObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([account])) as? [[String: Any]]
        )
        backupObject[0]["notes"] = "stale private note"
        try JSONSerialization.data(withJSONObject: backupObject).write(
            to: directory.appendingPathComponent("Accounts.backup.json")
        )

        _ = try repository.load()

        let backup = String(decoding: try Data(
            contentsOf: directory.appendingPathComponent("Accounts.backup.json")
        ), as: UTF8.self)
        XCTAssertFalse(backup.contains("stale private note"))
    }
}

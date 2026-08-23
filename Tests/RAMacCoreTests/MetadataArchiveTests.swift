import Foundation
import XCTest
@testable import RAMacCore

final class MetadataArchiveTests: XCTestCase {
    func testManagedAccountAcceptsOnlyRobloxCDNAvatarURLs() {
        let allowed = ManagedAccount(
            userID: 1,
            username: "user",
            displayName: "User",
            avatarURLString: "https://tr.rbxcdn.com/avatar.png"
        )
        let blocked = ManagedAccount(
            userID: 2,
            username: "other",
            displayName: "Other",
            avatarURLString: "https://localhost/avatar.png"
        )

        XCTAssertEqual(allowed.avatarURL?.host, "tr.rbxcdn.com")
        XCTAssertNil(blocked.avatarURL)
        XCTAssertNil(blocked.avatarURLString)
    }

    func testDefaultExportContainsNoSessionsOrPrivateLinks() throws {
        let account = ManagedAccount(
            userID: 1,
            username: "user",
            displayName: "User",
            notes: "private profile note",
            savedServer: "https://www.roblox.com/games/1?privateServerLinkCode=secret-link"
        )
        let launchSet = LaunchSet(
            name: "Private",
            placeID: 1,
            serverStrategy: .privateServerLink("https://www.roblox.com/games/1?privateServerLinkCode=secret-link")
        )
        let data = try MetadataArchiveService().exportData(
            accounts: [account],
            groups: [],
            experiences: [],
            launchSets: [launchSet]
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret-link"))
        XCTAssertFalse(text.contains(".ROBLOSECURITY"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authentication-ticket"))
        XCTAssertFalse(text.contains("private profile note"))
    }

    func testImportMatchesExistingAccountByRobloxUserIDAndKeepsLocalID() throws {
        let existing = ManagedAccount(
            id: UUID(),
            userID: 5,
            username: "old",
            displayName: "Old",
            alias: "Local",
            notes: "local encrypted note"
        )
        let imported = ManagedAccount(
            id: UUID(),
            userID: 5,
            username: "new",
            displayName: "New",
            alias: "Backup",
            notes: "old backup note"
        )
        let data = try MetadataArchiveService().exportData(
            accounts: [imported], groups: ["Wave"], experiences: [], launchSets: []
        )
        let result = try MetadataArchiveService().importData(
            data,
            existingAccounts: [existing],
            existingGroups: [],
            existingExperiences: [],
            existingLaunchSets: []
        )
        XCTAssertEqual(result.accounts.count, 1)
        XCTAssertEqual(result.accounts[0].id, existing.id)
        XCTAssertEqual(result.accounts[0].username, "new")
        XCTAssertEqual(result.accounts[0].notes, "local encrypted note")
        XCTAssertEqual(result.importedAccountCount, 0)
    }

    func testImportRejectsDuplicateAccountUUIDsAndRobloxUserIDs() throws {
        let sharedID = UUID()
        let duplicateArchives = [
            [
                ManagedAccount(id: sharedID, userID: 1, username: "one", displayName: "One"),
                ManagedAccount(id: sharedID, userID: 2, username: "two", displayName: "Two")
            ],
            [
                ManagedAccount(userID: 3, username: "three", displayName: "Three"),
                ManagedAccount(userID: 3, username: "other-three", displayName: "Other Three")
            ]
        ]

        for accounts in duplicateArchives {
            let data = try JSONEncoder().encode(MetadataArchive(
                accounts: accounts,
                groups: [],
                experiences: [],
                launchSets: []
            ))
            XCTAssertThrowsError(try MetadataArchiveService().importData(
                data,
                existingAccounts: [],
                existingGroups: [],
                existingExperiences: [],
                existingLaunchSets: []
            ))
        }
    }

    func testActiveLaunchRecordHasNoSecretFields() throws {
        let record = ActiveLaunchTargetRecord(
            accountID: UUID(),
            processIdentifier: 123,
            placeID: 1818,
            targetKind: .publicJob,
            jobID: "00000000-0000-0000-0000-000000000001"
        )
        let data = try JSONEncoder().encode(record)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("ticket"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(text.contains("ROBLOSECURITY"))
    }

    func testImportRemapsLaunchSetToTheExistingLocalAccountID() throws {
        let local = ManagedAccount(id: UUID(), userID: 5, username: "local", displayName: "Local")
        let backup = ManagedAccount(id: UUID(), userID: 5, username: "backup", displayName: "Backup")
        let importedAssignment = WindowLayoutAssignment(
            accountID: backup.id,
            displayID: "display-1",
            displayName: "Display",
            displayPixelWidth: 2560,
            displayPixelHeight: 1440,
            region: .left
        )
        let set = LaunchSet(
            name: "Team",
            accountIDs: [backup.id],
            placeID: 1818,
            windowArrangement: .custom([importedAssignment])
        )
        let service = MetadataArchiveService()
        let data = try service.exportData(
            accounts: [backup],
            groups: [],
            experiences: [],
            launchSets: [set]
        )

        let result = try service.importData(
            data,
            existingAccounts: [local],
            existingGroups: [],
            existingExperiences: [],
            existingLaunchSets: []
        )

        XCTAssertEqual(result.launchSets.first?.accountIDs, [local.id])
        guard case .custom(let assignments) = result.launchSets.first?.windowArrangement else {
            return XCTFail("Expected a custom window arrangement")
        }
        XCTAssertEqual(assignments.first?.accountID, local.id)
        XCTAssertEqual(assignments.first?.region, .left)
    }

    func testLaunchSetWithoutWindowPolicyUsesSavedPlacements() throws {
        let launchSet = LaunchSet(name: "Legacy", placeID: 1818)
        let encoded = try JSONEncoder().encode(launchSet)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["windowArrangement"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(LaunchSet.self, from: legacyData)

        XCTAssertEqual(decoded.windowArrangement, .savedPlacements)
        XCTAssertNil(decoded.launchSettings)
    }
}

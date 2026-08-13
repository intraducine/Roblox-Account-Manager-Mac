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
    }

    func testImportMatchesExistingAccountByRobloxUserIDAndKeepsLocalID() throws {
        let existing = ManagedAccount(id: UUID(), userID: 5, username: "old", displayName: "Old", alias: "Local")
        let imported = ManagedAccount(id: UUID(), userID: 5, username: "new", displayName: "New", alias: "Backup")
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
        XCTAssertEqual(result.importedAccountCount, 0)
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
        let set = LaunchSet(name: "Team", accountIDs: [backup.id], placeID: 1818)
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
    }
}

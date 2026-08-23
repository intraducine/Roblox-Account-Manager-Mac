import XCTest
@testable import RAMacCore

final class LaunchSetTests: XCTestCase {
    func testLaunchSettingsOverrideRoundTripsWithLaunchSet() throws {
        let expected = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 8,
            overridesVolume: true,
            volume: 0.75
        )
        let launchSet = LaunchSet(name: "Custom", placeID: 1, launchSettings: expected)

        let decoded = try JSONDecoder().decode(
            LaunchSet.self,
            from: JSONEncoder().encode(launchSet)
        )

        XCTAssertEqual(decoded.launchSettings, expected)
    }

    func testSelectingAGroupSelectsEveryCurrentMemberAndKeepsExistingAccounts() {
        let existing = account(userID: 1, groups: [])
        let firstMember = account(userID: 2, groups: ["Main"])
        let secondMember = account(userID: 3, groups: ["main", "Other"])
        let unrelated = account(userID: 4, groups: ["Other"])
        var launchSet = LaunchSet(
            name: "Group launch",
            accountIDs: [existing.id],
            placeID: 1
        )

        launchSet.setGroupSelection(
            "MAIN",
            selected: true,
            accounts: [existing, firstMember, secondMember, unrelated]
        )

        XCTAssertEqual(launchSet.groupNames, ["MAIN"])
        XCTAssertEqual(Set(launchSet.accountIDs), Set([existing.id, firstMember.id, secondMember.id]))
    }

    func testClearingAGroupClearsOnlyMembersNotKeptByAnotherSelectedGroup() {
        let firstOnly = account(userID: 1, groups: ["First"])
        let shared = account(userID: 2, groups: ["First", "Second"])
        let secondOnly = account(userID: 3, groups: ["Second"])
        let unrelated = account(userID: 4, groups: [])
        var launchSet = LaunchSet(
            name: "Overlapping groups",
            accountIDs: [firstOnly.id, shared.id, secondOnly.id, unrelated.id],
            groupNames: ["First", "Second"],
            placeID: 1
        )

        launchSet.setGroupSelection(
            "first",
            selected: false,
            accounts: [firstOnly, shared, secondOnly, unrelated]
        )

        XCTAssertEqual(launchSet.groupNames, ["Second"])
        XCTAssertEqual(Set(launchSet.accountIDs), Set([shared.id, secondOnly.id, unrelated.id]))
    }

    private func account(userID: Int64, groups: [String]) -> ManagedAccount {
        ManagedAccount(
            userID: userID,
            username: "user\(userID)",
            displayName: "User \(userID)",
            groups: groups
        )
    }
}

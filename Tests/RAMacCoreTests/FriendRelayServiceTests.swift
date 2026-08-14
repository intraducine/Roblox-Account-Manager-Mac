import Foundation
import XCTest
@testable import RAMacCore

final class FriendRelayServiceTests: XCTestCase {
    func testPlanBuildsShortestFriendshipLayersFromTheSourceAccount() async {
        let first = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let second = ManagedAccount(userID: 2, username: "second", displayName: "Second")
        let third = ManagedAccount(userID: 3, username: "third", displayName: "Third")
        let isolated = ManagedAccount(userID: 4, username: "isolated", displayName: "Isolated")
        let social = FriendRelaySocialMock(friendsByUserID: [
            1: [2],
            2: [1, 3],
            3: [2],
            4: []
        ])
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(presenceAttempts: 1, presencePollNanoseconds: 0)
        )

        let plan = await service.plan(
            accounts: [first, second, third, isolated],
            sourceAccountIDs: [first.id]
        )

        XCTAssertEqual(plan.levels[first.id], 0)
        XCTAssertEqual(plan.levels[second.id], 1)
        XCTAssertEqual(plan.levels[third.id], 2)
        XCTAssertNil(plan.levels[isolated.id])
        XCTAssertEqual(
            plan.availableParent(for: third.id, joinedAccountIDs: [first.id, second.id]),
            second.id
        )
    }

    func testServerConfirmationRequiresTheExactPlaceAndJob() async {
        let account = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let social = FriendRelaySocialMock(
            friendsByUserID: [:],
            presencesByUserID: [
                1: [
                    RobloxSocialPresence(
                        userPresenceType: RobloxPresenceType.inExperience.rawValue,
                        placeId: 1818,
                        gameId: "wrong-job",
                        userId: 1
                    ),
                    RobloxSocialPresence(
                        userPresenceType: RobloxPresenceType.inExperience.rawValue,
                        placeId: 1818,
                        gameId: "target-job",
                        userId: 1
                    )
                ]
            ]
        )
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(presenceAttempts: 2, presencePollNanoseconds: 0)
        )

        let result = await service.waitForServer(
            account: account,
            session: "session",
            placeID: 1818,
            jobID: "target-job"
        )

        XCTAssertEqual(result, .arrived)
        let requestCount = await social.presenceRequestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testServerConfirmationTimesOutInsteadOfTreatingAnyExperienceAsSuccess() async {
        let account = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let social = FriendRelaySocialMock(
            friendsByUserID: [:],
            presencesByUserID: [
                1: [RobloxSocialPresence(
                    userPresenceType: RobloxPresenceType.inExperience.rawValue,
                    placeId: 999,
                    gameId: "another-job",
                    userId: 1
                )]
            ]
        )
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(presenceAttempts: 1, presencePollNanoseconds: 0)
        )

        let result = await service.waitForServer(
            account: account,
            session: "session",
            placeID: 1818,
            jobID: "target-job"
        )

        XCTAssertEqual(result, .timedOut)
    }
}

private actor FriendRelaySocialMock: RobloxSocialProviding {
    private let friendsByUserID: [Int64: [Int64]]
    private var presencesByUserID: [Int64: [RobloxSocialPresence]]
    private var presenceRequests = 0

    init(
        friendsByUserID: [Int64: [Int64]],
        presencesByUserID: [Int64: [RobloxSocialPresence]] = [:]
    ) {
        self.friendsByUserID = friendsByUserID
        self.presencesByUserID = presencesByUserID
    }

    func friends(of userID: Int64) -> [RobloxSocialUser] {
        friendsByUserID[userID, default: []].map {
            RobloxSocialUser(id: $0, name: "user_\($0)", displayName: "User \($0)")
        }
    }

    func users(for userIDs: [Int64]) -> [RobloxSocialUser] {
        userIDs.map { RobloxSocialUser(id: $0, name: "user_\($0)", displayName: "User \($0)") }
    }

    func onlineFriends(of userID: Int64, session: String) -> [RobloxVisibleFriend] { [] }

    func presences(for userIDs: [Int64], session: String?) -> [RobloxSocialPresence] {
        presenceRequests += 1
        return userIDs.compactMap { userID in
            guard var values = presencesByUserID[userID], !values.isEmpty else { return nil }
            let value = values.removeFirst()
            presencesByUserID[userID] = values.isEmpty ? [value] : values
            return value
        }
    }

    func presenceRequestCount() -> Int { presenceRequests }
}

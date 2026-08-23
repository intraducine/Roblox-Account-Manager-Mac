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

    func testPlanKeepsAFriendshipReportedByTheOtherAccountWhenOneLookupFails() async {
        let first = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let second = ManagedAccount(userID: 2, username: "second", displayName: "Second")
        let social = FriendRelaySocialMock(
            friendsByUserID: [2: [1]],
            friendErrorsByUserID: [1: .networkUnavailable]
        )
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(presenceAttempts: 1)
        )

        let plan = await service.plan(
            accounts: [first, second],
            sourceAccountIDs: [first.id]
        )

        XCTAssertEqual(plan.levels[second.id], 1)
        XCTAssertEqual(plan.friendAccountIDs[first.id], [second.id])
        XCTAssertEqual(plan.friendAccountIDs[second.id], [first.id])
        XCTAssertEqual(plan.lookupFailures[first.id], "The Roblox service could not be reached.")
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

    func testServerConfirmationHasAHardOverallDeadline() async {
        let account = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let social = FriendRelaySocialMock(
            friendsByUserID: [:],
            presenceDelayNanoseconds: 5_000_000_000
        )
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(
                presenceAttempts: 15,
                presencePollNanoseconds: 1_000_000_000,
                confirmationTimeoutNanoseconds: 20_000_000
            )
        )

        let clock = ContinuousClock()
        let start = clock.now
        let result = await service.waitForServer(
            account: account,
            session: "session",
            placeID: 1818,
            jobID: "target-job"
        )
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(elapsed, .milliseconds(500))
    }

    func testSignedOutServerConfirmationStopsWithoutRetrying() async {
        let account = ManagedAccount(userID: 1, username: "first", displayName: "First")
        let social = FriendRelaySocialMock(
            friendsByUserID: [:],
            presenceError: .signedOut
        )
        let service = FriendRelayService(
            social: social,
            configuration: FriendRelayConfiguration(
                presenceAttempts: 15,
                presencePollNanoseconds: 0
            )
        )

        let result = await service.waitForServer(
            account: account,
            session: "session",
            placeID: 1818,
            jobID: "target-job"
        )

        XCTAssertEqual(result, .unavailable("The Roblox sign-in has expired."))
        let requestCount = await social.presenceRequestCount()
        XCTAssertEqual(requestCount, 1)
    }
}

private actor FriendRelaySocialMock: RobloxSocialProviding {
    private let friendsByUserID: [Int64: [Int64]]
    private let friendErrorsByUserID: [Int64: RobloxSocialAPIError]
    private var presencesByUserID: [Int64: [RobloxSocialPresence]]
    private let presenceDelayNanoseconds: UInt64
    private let presenceError: RobloxSocialAPIError?
    private var presenceRequests = 0

    init(
        friendsByUserID: [Int64: [Int64]],
        friendErrorsByUserID: [Int64: RobloxSocialAPIError] = [:],
        presencesByUserID: [Int64: [RobloxSocialPresence]] = [:],
        presenceDelayNanoseconds: UInt64 = 0,
        presenceError: RobloxSocialAPIError? = nil
    ) {
        self.friendsByUserID = friendsByUserID
        self.friendErrorsByUserID = friendErrorsByUserID
        self.presencesByUserID = presencesByUserID
        self.presenceDelayNanoseconds = presenceDelayNanoseconds
        self.presenceError = presenceError
    }

    func friends(of userID: Int64) throws -> [RobloxSocialUser] {
        if let error = friendErrorsByUserID[userID] { throw error }
        return friendsByUserID[userID, default: []].map {
            RobloxSocialUser(id: $0, name: "user_\($0)", displayName: "User \($0)")
        }
    }

    func users(for userIDs: [Int64]) -> [RobloxSocialUser] {
        userIDs.map { RobloxSocialUser(id: $0, name: "user_\($0)", displayName: "User \($0)") }
    }

    func onlineFriends(of userID: Int64, session: String) -> [RobloxVisibleFriend] { [] }

    func presences(for userIDs: [Int64], session: String?) async throws -> [RobloxSocialPresence] {
        presenceRequests += 1
        if presenceDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: presenceDelayNanoseconds)
        }
        if let presenceError { throw presenceError }
        return userIDs.compactMap { userID in
            guard var values = presencesByUserID[userID], !values.isEmpty else { return nil }
            let value = values.removeFirst()
            presencesByUserID[userID] = values.isEmpty ? [value] : values
            return value
        }
    }

    func presenceRequestCount() -> Int { presenceRequests }
}

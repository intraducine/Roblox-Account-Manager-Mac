import XCTest
@testable import RAMacCore

final class PlayerDiscoveryServiceTests: XCTestCase {
    func testAuthenticatedFriendUnionKeepsEverySourceAccount() async throws {
        let first = account(userID: 1)
        let second = account(userID: 2)
        let target = visibleFriend(userID: 50, placeID: 100, jobID: jobID(1))
        let social = MockSocial(online: [1: [target], 2: [target]])

        let result = await PlayerDiscoveryService(social: social).discover(sources: [
            source(first), source(second)
        ])

        XCTAssertEqual(result.players.count, 1)
        XCTAssertEqual(result.players[0].candidate.sourceAccountIDs, [first.id, second.id])
        XCTAssertEqual(result.players[0].verification, .friendTarget)
        XCTAssertFalse(result.players[0].isPubliclyVisible)
        XCTAssertFalse(result.usedPublicPresenceOnly)
    }

    func testFriendDiscoveryDoesNotCallPublicFriendsOrPresence() async {
        let social = MockSocial(online: [
            1: [visibleFriend(userID: 50, placeID: 100, jobID: jobID(1))]
        ])

        _ = await PlayerDiscoveryService(social: social).discover(sources: [source(account(userID: 1))])

        let counts = await social.requestCounts()
        XCTAssertEqual(counts.online, 1)
        XCTAssertEqual(counts.publicFriends, 0)
        XCTAssertEqual(counts.presence, 0)
    }

    func testSourceRequestsRunOneAtATime() async {
        let social = MockSocial(
            online: [
                1: [visibleFriend(userID: 51, placeID: 100, jobID: jobID(1))],
                2: [visibleFriend(userID: 52, placeID: 100, jobID: jobID(2))],
                3: [visibleFriend(userID: 53, placeID: 100, jobID: jobID(3))]
            ],
            requestDelayNanoseconds: 20_000_000
        )

        _ = await PlayerDiscoveryService(social: social).discover(sources: [
            source(account(userID: 1)), source(account(userID: 2)), source(account(userID: 3))
        ])

        let maximumConcurrentRequests = await social.maximumConcurrentOnlineRequests()
        XCTAssertEqual(maximumConcurrentRequests, 1)
    }

    func testOfflineFriendsAreNotShown() async {
        let social = MockSocial(online: [
            1: [visibleFriend(userID: 50, placeID: nil, jobID: nil, type: 1)]
        ])

        let result = await PlayerDiscoveryService(social: social)
            .discover(sources: [source(account(userID: 1))])

        XCTAssertTrue(result.players.isEmpty)
    }

    func testMissingJobIDDoesNotInventATarget() async {
        let social = MockSocial(online: [
            1: [visibleFriend(userID: 50, placeID: 100, jobID: nil)]
        ])

        let result = await PlayerDiscoveryService(social: social)
            .discover(sources: [source(account(userID: 1))])

        XCTAssertEqual(result.players.first?.verification, .noServerSupplied)
    }

    func testPartialSourceFailureRetainsOtherAccountResults() async {
        let social = MockSocial(
            online: [1: [visibleFriend(userID: 50, placeID: 100, jobID: jobID(1))]],
            failingOnlineUserIDs: [2]
        )
        let result = await PlayerDiscoveryService(social: social).discover(sources: [
            source(account(userID: 1)), source(account(userID: 2))
        ])

        XCTAssertEqual(result.players.count, 1)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testConflictingFriendResponsesKeepTheMoreCompleteTarget() async {
        let partial = visibleFriend(userID: 50, placeID: 100, jobID: nil)
        let complete = visibleFriend(userID: 50, placeID: 101, jobID: jobID(2))
        let social = MockSocial(online: [1: [partial], 2: [complete]])

        let result = await PlayerDiscoveryService(social: social).discover(sources: [
            source(account(userID: 1)), source(account(userID: 2))
        ])

        XCTAssertTrue(result.players[0].conflictingPresenceWasObserved)
        XCTAssertEqual(result.players[0].presence.placeID, 101)
        XCTAssertEqual(result.players[0].presence.jobID, jobID(2))
    }

    func testOnlineFriendResultsAreCachedForOneMinute() async {
        let social = MockSocial(online: [
            1: [visibleFriend(userID: 50, placeID: 100, jobID: jobID(1))]
        ])
        let service = PlayerDiscoveryService(social: social)
        let savedSource = source(account(userID: 1))

        _ = await service.discover(sources: [savedSource])
        _ = await service.discover(sources: [savedSource])

        let counts = await social.requestCounts()
        XCTAssertEqual(counts.online, 1)
    }

    func testFriendTargetContinueAndRefreshNeverSearchPublicServers() async {
        let social = MockSocial(online: [:])
        let service = PlayerDiscoveryService(social: social)
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(userID: 50, username: "friend", displayName: "Friend", sourceAccountIDs: []),
            presence: PlayerPresenceSnapshot(
                userID: 50,
                presenceType: .inExperience,
                placeID: 100,
                jobID: jobID(1)
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        let continued = await service.continueVerification(for: player)
        let refreshed = await service.refreshVerification(for: player)
        XCTAssertEqual(continued, .friendTarget)
        XCTAssertEqual(refreshed, .friendTarget)
        let counts = await social.requestCounts()
        XCTAssertEqual(counts.online, 0)
        XCTAssertEqual(counts.publicFriends, 0)
        XCTAssertEqual(counts.presence, 0)
    }

    private func account(userID: Int64) -> ManagedAccount {
        ManagedAccount(userID: userID, username: "source\(userID)", displayName: "Source \(userID)")
    }

    private func source(_ account: ManagedAccount) -> PlayerDiscoverySource {
        PlayerDiscoverySource(account: account, session: "cookie-\(account.userID)")
    }

    private func jobID(_ value: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", value)
    }

    private func visibleFriend(
        userID: Int64,
        placeID: Int64?,
        jobID: String?,
        type: Int = 2
    ) -> RobloxVisibleFriend {
        RobloxVisibleFriend(
            id: userID,
            name: "friend\(userID)",
            displayName: "Friend \(userID)",
            userPresenceType: type,
            placeId: placeID,
            rootPlaceId: placeID,
            gameId: jobID,
            universeId: 200,
            lastLocation: "Test Experience"
        )
    }
}

private actor MockSocial: RobloxSocialProviding {
    let onlineByUserID: [Int64: [RobloxVisibleFriend]]
    let failingOnlineUserIDs: Set<Int64>
    let requestDelayNanoseconds: UInt64
    var onlineCalls = 0
    var publicFriendCalls = 0
    var presenceCalls = 0
    var activeOnlineRequests = 0
    var maximumActiveOnlineRequests = 0

    init(
        online: [Int64: [RobloxVisibleFriend]],
        failingOnlineUserIDs: Set<Int64> = [],
        requestDelayNanoseconds: UInt64 = 0
    ) {
        onlineByUserID = online
        self.failingOnlineUserIDs = failingOnlineUserIDs
        self.requestDelayNanoseconds = requestDelayNanoseconds
    }

    func friends(of userID: Int64) async throws -> [RobloxSocialUser] {
        publicFriendCalls += 1
        return []
    }

    func users(for userIDs: [Int64]) async throws -> [RobloxSocialUser] { [] }

    func onlineFriends(of userID: Int64, session: String) async throws -> [RobloxVisibleFriend] {
        onlineCalls += 1
        activeOnlineRequests += 1
        maximumActiveOnlineRequests = max(maximumActiveOnlineRequests, activeOnlineRequests)
        defer { activeOnlineRequests -= 1 }
        if requestDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: requestDelayNanoseconds)
        }
        if failingOnlineUserIDs.contains(userID) { throw RobloxSocialAPIError.signedOut }
        return onlineByUserID[userID] ?? []
    }

    func presences(for userIDs: [Int64], session: String?) async throws -> [RobloxSocialPresence] {
        presenceCalls += 1
        return []
    }

    func requestCounts() -> (online: Int, publicFriends: Int, presence: Int) {
        (onlineCalls, publicFriendCalls, presenceCalls)
    }

    func maximumConcurrentOnlineRequests() -> Int { maximumActiveOnlineRequests }
}

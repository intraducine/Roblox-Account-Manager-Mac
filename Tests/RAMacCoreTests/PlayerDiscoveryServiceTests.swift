import XCTest
@testable import RAMacCore

final class PlayerDiscoveryServiceTests: XCTestCase {
    func testFriendUnionDeduplicatesAndKeepsEverySourceAccount() async throws {
        let first = account(id: UUID(), userID: 1)
        let second = account(id: UUID(), userID: 2)
        let shared = RobloxSocialUser(id: 50, name: "shared", displayName: "Shared")
        let social = MockSocial(
            friends: [1: [shared], 2: [shared]],
            presences: [presence(userID: 50, placeID: 100, jobID: jobID(1))]
        )
        let servers = MockServers(pages: ["first": .init(data: [server(id: jobID(1))])])
        let result = await PlayerDiscoveryService(social: social, serverProvider: servers)
            .discover(sourceAccounts: [first, second])

        XCTAssertEqual(result.players.count, 1)
        XCTAssertEqual(result.players[0].candidate.sourceAccountIDs, [first.id, second.id])
        XCTAssertTrue(result.players[0].isPubliclyVisible)
        XCTAssertTrue(result.players[0].verification.isVerifiedPublic)
    }

    func testPresenceRequestsUseConfiguredBatches() async {
        let friends = (1...5).map { RobloxSocialUser(id: Int64($0 + 100), name: "u\($0)", displayName: "U\($0)") }
        let values = friends.map { presence(userID: $0.id, placeID: nil, jobID: nil, type: 0) }
        let social = MockSocial(friends: [1: friends], presences: values)
        let service = PlayerDiscoveryService(
            social: social,
            serverProvider: MockServers(pages: [:]),
            configuration: .init(presenceBatchSize: 2, maximumConcurrentRequests: 2)
        )
        _ = await service.discover(sourceAccounts: [account(id: UUID(), userID: 1)])
        let batches = await social.requestedPresenceBatches()
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches.map(\.count).sorted(), [1, 2, 2])
    }

    func testServerFoundOnLaterPage() async {
        let wanted = jobID(9)
        let social = MockSocial(
            friends: [1: [.init(id: 3, name: "target", displayName: "Target")]],
            presences: [presence(userID: 3, placeID: 200, jobID: wanted)]
        )
        let servers = MockServers(pages: [
            "first": .init(nextPageCursor: "second", data: [server(id: jobID(1))]),
            "second": .init(data: [server(id: wanted, playing: 4, maxPlayers: 10)])
        ])
        let result = await PlayerDiscoveryService(social: social, serverProvider: servers)
            .discover(sourceAccounts: [account(id: UUID(), userID: 1)])
        guard case .verifiedPublic(let found) = result.players.first?.verification else {
            return XCTFail("Expected a verified server")
        }
        XCTAssertEqual(found.id, wanted)
        let serverCalls = await servers.callCount()
        XCTAssertEqual(serverCalls, 2)
    }

    func testSearchBudgetDoesNotCallServerPrivate() async {
        let wanted = jobID(8)
        let social = MockSocial(
            friends: [1: [.init(id: 3, name: "target", displayName: "Target")]],
            presences: [presence(userID: 3, placeID: 200, jobID: wanted)]
        )
        let servers = EndlessServers()
        let result = await PlayerDiscoveryService(
            social: social,
            serverProvider: servers,
            configuration: .init(maximumServerPages: 3)
        ).discover(sourceAccounts: [account(id: UUID(), userID: 1)])
        guard case .unconfirmed(let pages) = result.players.first?.verification else {
            return XCTFail("Expected an unconfirmed server")
        }
        XCTAssertEqual(pages, 3)
        let serverCalls = await servers.callCount()
        XCTAssertEqual(serverCalls, 3)
    }

    func testPartialSourceFailureRetainsOtherAccountResults() async {
        let social = MockSocial(
            friends: [1: [.init(id: 10, name: "ok", displayName: "OK")]],
            presences: [presence(userID: 10, placeID: 100, jobID: jobID(4))],
            failingFriendUserIDs: [2]
        )
        let servers = MockServers(pages: ["first": .init(data: [server(id: jobID(4))])])
        let result = await PlayerDiscoveryService(social: social, serverProvider: servers)
            .discover(sourceAccounts: [account(id: UUID(), userID: 1), account(id: UUID(), userID: 2)])
        XCTAssertEqual(result.players.count, 1)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testConflictingPresenceKeepsOnePlayerAndRecordsConflict() async {
        let user = RobloxSocialUser(id: 10, name: "target", displayName: "Target")
        let social = MockSocial(
            friends: [1: [user]],
            presences: [
                presence(userID: 10, placeID: 100, jobID: jobID(1)),
                presence(userID: 10, placeID: 101, jobID: nil)
            ]
        )
        let servers = MockServers(pages: ["first": .init(data: [server(id: jobID(1))])])
        let result = await PlayerDiscoveryService(social: social, serverProvider: servers)
            .discover(sourceAccounts: [account(id: UUID(), userID: 1)])
        XCTAssertEqual(result.players.count, 1)
        XCTAssertTrue(result.players[0].conflictingPresenceWasObserved)
        XCTAssertEqual(result.players[0].presence.jobID, jobID(1))
    }

    func testPresenceAndServerPagesAreCachedForOneMinute() async {
        let target = RobloxSocialUser(id: 10, name: "target", displayName: "Target")
        let social = MockSocial(
            friends: [1: [target]],
            presences: [presence(userID: 10, placeID: 100, jobID: jobID(2))]
        )
        let servers = MockServers(pages: ["first": .init(data: [server(id: jobID(2))])])
        let service = PlayerDiscoveryService(social: social, serverProvider: servers)
        let source = account(id: UUID(), userID: 1)
        _ = await service.discover(sourceAccounts: [source])
        _ = await service.discover(sourceAccounts: [source])
        let presenceCalls = await social.presenceCallCount()
        let serverCalls = await servers.callCount()
        XCTAssertEqual(presenceCalls, 1)
        XCTAssertEqual(serverCalls, 1)
    }

    func testOfflineAndMissingPresenceAreNotGuessedAsHidden() async {
        let offline = RobloxSocialUser(id: 10, name: "offline", displayName: "Offline")
        let missing = RobloxSocialUser(id: 11, name: "missing", displayName: "Missing")
        let social = MockSocial(
            friends: [1: [offline, missing]],
            presences: [presence(userID: offline.id, placeID: nil, jobID: nil, type: 0)]
        )

        let result = await PlayerDiscoveryService(social: social, serverProvider: MockServers(pages: [:]))
            .discover(sourceAccounts: [account(id: UUID(), userID: 1)])

        XCTAssertTrue(result.players.isEmpty)
        XCTAssertTrue(result.usedPublicPresenceOnly)
    }

    func testMissingFriendNamesUseThePublicUserLookup() async {
        let social = MockSocial(
            friends: [1: [.init(id: 10, name: "", displayName: "")]],
            presences: [presence(userID: 10, placeID: 100, jobID: jobID(1))],
            profiles: [.init(id: 10, name: "resolved", displayName: "Resolved")]
        )
        let servers = MockServers(pages: ["first": .init(data: [server(id: jobID(1))])])

        let result = await PlayerDiscoveryService(social: social, serverProvider: servers)
            .discover(sourceAccounts: [account(id: UUID(), userID: 1)])

        XCTAssertEqual(result.players.first?.candidate.username, "resolved")
        XCTAssertEqual(result.players.first?.candidate.displayName, "Resolved")
    }

    private func account(id: UUID, userID: Int64) -> ManagedAccount {
        ManagedAccount(id: id, userID: userID, username: "source", displayName: "Source")
    }
    private func jobID(_ value: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", value) }
    private func server(id: String, playing: Int = 1, maxPlayers: Int = 10) -> RobloxPublicServer {
        .init(id: id, maxPlayers: maxPlayers, playing: playing)
    }
    private func presence(
        userID: Int64,
        placeID: Int64?,
        jobID: String?,
        type: Int = 2
    ) -> RobloxSocialPresence {
        .init(userPresenceType: type, lastLocation: "Test", placeId: placeID, gameId: jobID, userId: userID)
    }
}

private actor MockSocial: RobloxSocialProviding {
    let friendsByUserID: [Int64: [RobloxSocialUser]]
    let presenceValues: [RobloxSocialPresence]
    let profileValues: [RobloxSocialUser]
    let failingFriendUserIDs: Set<Int64>
    var batches: [[Int64]] = []

    init(
        friends: [Int64: [RobloxSocialUser]],
        presences: [RobloxSocialPresence],
        profiles: [RobloxSocialUser] = [],
        failingFriendUserIDs: Set<Int64> = []
    ) {
        friendsByUserID = friends
        presenceValues = presences
        profileValues = profiles
        self.failingFriendUserIDs = failingFriendUserIDs
    }

    func friends(of userID: Int64) async throws -> [RobloxSocialUser] {
        if failingFriendUserIDs.contains(userID) { throw RobloxSocialAPIError.networkUnavailable }
        return friendsByUserID[userID] ?? []
    }
    func users(for userIDs: [Int64]) async throws -> [RobloxSocialUser] {
        profileValues.filter { userIDs.contains($0.id) }
    }
    func onlineFriends(of userID: Int64, session: String) async throws -> [RobloxVisibleFriend] { [] }
    func presences(for userIDs: [Int64], session: String?) async throws -> [RobloxSocialPresence] {
        batches.append(userIDs)
        return presenceValues.filter { userIDs.contains($0.userId) }
    }
    func requestedPresenceBatches() -> [[Int64]] { batches }
    func presenceCallCount() -> Int { batches.count }
}

private actor MockServers: RobloxPublicServerProviding {
    let pages: [String: RobloxPublicServerPage]
    var calls = 0
    init(pages: [String: RobloxPublicServerPage]) { self.pages = pages }
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage {
        calls += 1
        return pages[cursor ?? "first"] ?? .init(data: [])
    }
    func callCount() -> Int { calls }
}

private actor EndlessServers: RobloxPublicServerProviding {
    var calls = 0
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage {
        calls += 1
        return .init(nextPageCursor: "page-\(calls)", data: [])
    }
    func callCount() -> Int { calls }
}

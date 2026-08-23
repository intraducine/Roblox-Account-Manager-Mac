import XCTest
@testable import RAMacCore

final class JoinAssessmentServiceTests: XCTestCase {
    func testFullAndPartialCapacityNeverSilentlyDropsAccounts() async {
        let accounts = (1...4).map {
            ManagedAccount(id: UUID(), userID: Int64($0), username: "u\($0)", displayName: "U\($0)")
        }
        let health = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, AccountHealth.ready(lastChecked: Date())) })
        let target = PlayerJoinTarget(
            placeID: 1,
            jobID: "job",
            verification: .verifiedPublic(.init(id: "job", maxPlayers: 10, playing: 8))
        )
        let result = await JoinAssessmentService().assess(
            target: target,
            accounts: accounts,
            health: health,
            runningAccountIDs: []
        )
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.filter { $0.state == .expectedToJoin }.count, 2)
        XCTAssertEqual(result.filter { $0.state == .serverHasNoSpace }.count, 2)
    }

    func testSignedOutRunningAndUnknownAccountsHaveSeparateResults() async {
        let ready = ManagedAccount(userID: 1, username: "ready", displayName: "Ready")
        let signedOut = ManagedAccount(userID: 2, username: "out", displayName: "Out")
        let unknown = ManagedAccount(userID: 3, username: "unknown", displayName: "Unknown")
        let target = PlayerJoinTarget(
            placeID: 1,
            jobID: "job",
            verification: .verifiedPublic(.init(id: "job", maxPlayers: 10, playing: 0))
        )
        let result = await JoinAssessmentService().assess(
            target: target,
            accounts: [ready, signedOut, unknown],
            health: [ready.id: .ready(lastChecked: Date()), signedOut.id: .signedOut],
            runningAccountIDs: [ready.id]
        )
        XCTAssertEqual(result.map(\.state), [.alreadyRunning, .signedOut, .statusUnknown])
    }

    func testFriendTargetDoesNotNeedPublicCapacityData() async {
        let accounts = (1...3).map {
            ManagedAccount(userID: Int64($0), username: "u\($0)", displayName: "U\($0)")
        }
        let health = Dictionary(uniqueKeysWithValues: accounts.map {
            ($0.id, AccountHealth.ready(lastChecked: Date()))
        })
        let result = await JoinAssessmentService().assess(
            target: PlayerJoinTarget(placeID: 1, jobID: "job", verification: .friendTarget),
            accounts: accounts,
            health: health,
            runningAccountIDs: []
        )

        XCTAssertEqual(result.map(\.state), [.expectedToJoin, .expectedToJoin, .expectedToJoin])
        XCTAssertTrue(result.allSatisfy { $0.explanation.contains("Roblox will decide") })
    }
}

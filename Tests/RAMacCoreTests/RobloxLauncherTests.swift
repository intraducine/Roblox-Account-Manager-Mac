import XCTest
@testable import RAMacCore

final class RobloxLauncherTests: XCTestCase {
    private let builder = RobloxLaunchURLBuilder()

    func testPublicLaunchURLUsesMacProtocolAndEncodedRequest() throws {
        let url = try builder.makeURL(
            ticket: "ticket-value",
            placeID: 920587237,
            trackerID: "123456789012",
            launchTime: 1_700_000_000_000
        )
        XCTAssertEqual(url.scheme, "roblox-player")
        XCTAssertTrue(url.absoluteString.contains("gameinfo:ticket-value"))
        XCTAssertTrue(url.absoluteString.contains("placeId%3D920587237"))
        XCTAssertTrue(url.absoluteString.contains("%26isPlayTogetherGame%3Dfalse"))
    }

    func testJobAndPrivateServerRequests() throws {
        let job = try builder.makeURL(
            ticket: "ticket",
            placeID: 10,
            target: .job("job-id"),
            trackerID: "123456789012",
            launchTime: 1
        )
        XCTAssertTrue(job.absoluteString.contains("RequestGameJob"))
        XCTAssertTrue(job.absoluteString.contains("gameId%3Djob-id"))

        let privateServer = try builder.makeURL(
            ticket: "ticket",
            placeID: 10,
            target: .privateServer(accessCode: "access", linkCode: "link"),
            trackerID: "123456789012",
            launchTime: 1
        )
        XCTAssertTrue(privateServer.absoluteString.contains("RequestPrivateGame"))
        XCTAssertTrue(privateServer.absoluteString.contains("accessCode%3Daccess"))
        XCTAssertTrue(privateServer.absoluteString.contains("linkCode%3Dlink"))
    }

    func testPrivateLinkParsing() {
        XCTAssertEqual(
            RobloxLaunchURLBuilder.privateLinkCode(
                from: "https://www.roblox.com/games/10/Name?privateServerLinkCode=abc-123"
            ),
            "abc-123"
        )
        XCTAssertNil(RobloxLaunchURLBuilder.privateLinkCode(from: "not a link"))
    }

    func testRejectsInvalidPlace() {
        XCTAssertThrowsError(try builder.makeURL(ticket: "ticket", placeID: 0))
    }
}

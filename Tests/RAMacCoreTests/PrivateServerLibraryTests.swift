import Foundation
import XCTest
@testable import RAMacCore

final class PrivateServerLibraryTests: XCTestCase {
    func testRepositoryRoundTripsPrivateServers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-private-server-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PrivateServerRepository(dataDirectory: directory)
        let server = SavedPrivateServer(
            name: "Friends server",
            placeID: 1818,
            link: "https://www.roblox.com/games/1818/Example?privateServerLinkCode=secret-code",
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )

        try repository.save([server])

        XCTAssertEqual(try repository.load(), [server])
    }

    func testPrivateServerPlaceIDRequiresACompleteRobloxPrivateLink() {
        XCTAssertEqual(
            RobloxLaunchURLBuilder.privateServerPlaceID(
                from: "https://www.roblox.com/games/1818/Example?privateServerLinkCode=secret-code"
            ),
            1818
        )
        XCTAssertNil(RobloxLaunchURLBuilder.privateServerPlaceID(
            from: "https://www.roblox.com/games/1818/Example"
        ))
        XCTAssertNil(RobloxLaunchURLBuilder.privateServerPlaceID(
            from: "https://evilroblox.com/games/1818/Example?privateServerLinkCode=secret-code"
        ))
        XCTAssertNil(RobloxLaunchURLBuilder.privateServerPlaceID(
            from: "https://www.roblox.com/share?code=secret-code&type=Server"
        ))
    }
}

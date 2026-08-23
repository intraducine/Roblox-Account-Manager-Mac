import XCTest
@testable import RAMacCore

final class RobloxGameReferenceTests: XCTestCase {
    func testReadsPlaceIDFromNumberAndRobloxGameLinks() {
        XCTAssertEqual(RobloxGameReference.placeID(from: "1818"), 1818)
        XCTAssertEqual(
            RobloxGameReference.placeID(from: "https://www.roblox.com/games/1818/Classic-Crossroads"),
            1818
        )
        XCTAssertEqual(
            RobloxGameReference.placeID(from: "roblox.com/games/1818/Classic-Crossroads?refPageId=test"),
            1818
        )
    }

    func testRejectsLookalikeLinksAndNonGamePages() {
        XCTAssertNil(RobloxGameReference.placeID(from: "https://evilroblox.com/games/1818"))
        XCTAssertNil(RobloxGameReference.placeID(from: "https://user:pass@roblox.com/games/1818"))
        XCTAssertNil(RobloxGameReference.placeID(from: "http://roblox.com/games/1818"))
        XCTAssertNil(RobloxGameReference.placeID(from: "https://roblox.com/users/1818/profile"))
        XCTAssertNil(RobloxGameReference.placeID(from: "not a game"))
    }
}

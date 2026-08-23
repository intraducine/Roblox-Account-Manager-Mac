import SwiftUI
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class LaunchControlsSupportTests: XCTestCase {
    func testChangingGameResetsManualJobID() {
        var placeID = "100"
        var serverSelection = RobloxServerSelection.manualJob("friend-job")
        let binding = placeIDBindingResettingServer(
            placeID: Binding(get: { placeID }, set: { placeID = $0 }),
            serverSelection: Binding(get: { serverSelection }, set: { serverSelection = $0 })
        )

        binding.wrappedValue = "200"

        XCTAssertEqual(placeID, "200")
        XCTAssertEqual(serverSelection, .automatic)
    }

    func testSameGameKeepsExplicitServerChoice() {
        var placeID = "100"
        var serverSelection = RobloxServerSelection.manualJob("chosen-job")
        let binding = placeIDBindingResettingServer(
            placeID: Binding(get: { placeID }, set: { placeID = $0 }),
            serverSelection: Binding(get: { serverSelection }, set: { serverSelection = $0 })
        )

        binding.wrappedValue = " 100 "

        XCTAssertEqual(serverSelection, .manualJob("chosen-job"))
    }
}

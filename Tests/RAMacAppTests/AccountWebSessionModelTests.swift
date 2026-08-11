import Foundation
import RAMacCore
import XCTest
@testable import RAMacApp

@MainActor
final class AccountWebSessionModelTests: XCTestCase {
    func testRobloxMainPageStaysInsideManagedWindow() throws {
        let url = try XCTUnwrap(URL(string: "https://www.roblox.com/my/account#!/security"))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: true),
            .allow
        )
    }

    func testSecureExternalFrameCanLoadWithoutAnExternalLinkWarning() throws {
        let url = try XCTUnwrap(URL(string: "https://security-check.example/frame"))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: false),
            .allow
        )
    }

    func testExternalMainPageStillNeedsConfirmation() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/account"))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: true),
            .openExternally(url)
        )
    }

    func testInsecureExternalFrameIsCancelled() throws {
        let url = try XCTUnwrap(URL(string: "http://example.com/frame"))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: false),
            .cancel
        )
    }

    func testRobloxPlayerLinkBecomesAManagedLaunch() throws {
        let url = try RobloxLaunchURLBuilder().makeURL(
            ticket: "page-ticket",
            placeID: 1818,
            trackerID: "123456789012",
            launchTime: 1
        )

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: false),
            .launchManaged(RobloxWebLaunchRequest(placeID: 1818, server: .automatic))
        )
    }

    func testUnreadableRobloxPlayerLinkDoesNotOpenTheNormalClient() throws {
        let url = try XCTUnwrap(URL(string: "roblox-player:unrecognized"))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: true),
            .unsupportedRobloxLaunch
        )
    }
}

import Foundation
import RAMacCore
import XCTest
@testable import RAMacApp

@MainActor
final class AccountWebSessionModelTests: XCTestCase {
    func testManagedSessionCookieIsSecureAndHTTPOnly() throws {
        let cookie = try XCTUnwrap(AccountWebSessionModel.managedSessionCookie(from: "test-session"))

        XCTAssertTrue(cookie.isSecure)
        XCTAssertTrue(cookie.isHTTPOnly)
        XCTAssertEqual(cookie.domain, ".roblox.com")
        XCTAssertEqual(cookie.value, "test-session")
    }

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

    func testRobloxPlayerLinkFromSubframeIsCancelled() throws {
        let url = try RobloxLaunchURLBuilder().makeURL(
            ticket: "page-ticket",
            placeID: 1818,
            trackerID: "123456789012",
            launchTime: 1
        )

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(
                for: url,
                targetIsMainFrame: false,
                sourceIsMainFrame: false
            ),
            .cancel
        )
    }

    func testRobloxPlayerLinkFromMainFrameBecomesAManagedLaunch() throws {
        let url = try RobloxLaunchURLBuilder().makeURL(
            ticket: "page-ticket",
            placeID: 1818,
            trackerID: "123456789012",
            launchTime: 1
        )

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(
                for: url,
                targetIsMainFrame: nil,
                sourceIsMainFrame: true
            ),
            .launchManaged(RobloxWebLaunchRequest(placeID: 1818, server: .automatic))
        )
    }

    func testLoginViewAllowsOnlyRobloxMainFrameOrigins() throws {
        XCTAssertTrue(LoginBrowserModel.allowsMainFrameNavigation(
            to: try XCTUnwrap(URL(string: "https://www.roblox.com/login"))
        ))
        XCTAssertFalse(LoginBrowserModel.allowsMainFrameNavigation(
            to: try XCTUnwrap(URL(string: "https://roblox.example/login"))
        ))
        XCTAssertFalse(LoginBrowserModel.allowsMainFrameNavigation(
            to: try XCTUnwrap(URL(string: "http://www.roblox.com/login"))
        ))
    }

    func testCurrentPrivateServerShareLinkBecomesAManagedLaunch() throws {
        let url = try XCTUnwrap(
            URL(string: "roblox://navigation/share_links?code=share-code&type=Server")
        )
        let request = try XCTUnwrap(RobloxWebLaunchRequestParser.parse(url))

        XCTAssertEqual(
            AccountWebSessionModel.navigationDecision(for: url, targetIsMainFrame: true),
            .launchManaged(request)
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

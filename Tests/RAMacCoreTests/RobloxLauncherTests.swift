import Darwin
import Foundation
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

    func testParallelBundleIdentifierIsStableAndUnique() {
        let first = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let second = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(
            ParallelRobloxLauncher.bundleIdentifier(for: first),
            "com.intraducine.RobloxAccountManager.instance.AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE"
        )
        XCTAssertNotEqual(
            ParallelRobloxLauncher.bundleIdentifier(for: first),
            ParallelRobloxLauncher.bundleIdentifier(for: second)
        )
    }

    func testParallelInfoPlistPatchPreservesRobloxMetadata() throws {
        let accountID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let source: [String: Any] = [
            "CFBundleIdentifier": "com.roblox.RobloxPlayer",
            "CFBundleExecutable": "RobloxPlayer",
            "CFBundleVersion": "7330989",
            "LSMultipleInstancesProhibited": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let patched = try ParallelRobloxLauncher.patchedInfoPlist(data, accountID: accountID)
        let object = try PropertyListSerialization.propertyList(from: patched, options: [], format: nil)
        let info = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "RobloxPlayer")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "7330989")
        XCTAssertEqual(info["LSMultipleInstancesProhibited"] as? Bool, false)
        XCTAssertEqual(
            info["CFBundleIdentifier"] as? String,
            ParallelRobloxLauncher.bundleIdentifier(for: accountID)
        )
    }

    func testLiveParallelCopyLaunchWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RAM_RUN_PARALLEL_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RAM_RUN_PARALLEL_INTEGRATION=1 to run the installed-Roblox integration test.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-parallel-integration-\(UUID().uuidString)", isDirectory: true)
        let launcher = ParallelRobloxLauncher(instancesRoot: root)
        let accountIDs = [UUID(), UUID()]
        addTeardownBlock {
            for accountID in accountIDs {
                _ = await launcher.stop(accountID: accountID)
            }
            await launcher.removeStaleCopies()
            try? FileManager.default.removeItem(at: root)
        }
        let invalidTicketURL = try builder.makeURL(
            ticket: "invalid-integration-test-ticket",
            placeID: 920587237,
            trackerID: "123456789012",
            launchTime: 1
        )

        let first = try await launcher.launch(invalidTicketURL, for: accountIDs[0])
        let second = try await launcher.launch(invalidTicketURL, for: accountIDs[1])
        XCTAssertGreaterThan(first.processIdentifier, 0)
        XCTAssertGreaterThan(second.processIdentifier, 0)
        XCTAssertNotEqual(first.processIdentifier, second.processIdentifier)
        let runningAfterLaunch = await launcher.runningAccountIDs(from: accountIDs)
        XCTAssertEqual(runningAfterLaunch, Set(accountIDs))
        XCTAssertEqual(kill(first.processIdentifier, 0), 0)
        XCTAssertEqual(kill(second.processIdentifier, 0), 0)

        for accountID in accountIDs {
            let stopped = await launcher.stop(accountID: accountID)
            XCTAssertTrue(stopped)
        }
        for _ in 0..<20 {
            if (await launcher.runningAccountIDs(from: accountIDs)).isEmpty { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let runningAfterStop = await launcher.runningAccountIDs(from: accountIDs)
        XCTAssertTrue(runningAfterStop.isEmpty)
        await launcher.removeStaleCopies()
    }
}

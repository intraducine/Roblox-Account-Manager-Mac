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

    func testParallelBundleIdentifierIsSharedForPermissionReuse() {
        let first = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let second = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(
            ParallelRobloxLauncher.bundleIdentifier(for: first),
            ParallelRobloxLauncher.parallelBundleIdentifier
        )
        XCTAssertEqual(
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
        let patched = try ParallelRobloxLauncher.patchedInfoPlist(
            data,
            accountID: accountID,
            sourceBundleVersion: "7330989"
        )
        let object = try PropertyListSerialization.propertyList(from: patched, options: [], format: nil)
        let info = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "RobloxPlayer")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "7330989")
        XCTAssertEqual(info["LSMultipleInstancesProhibited"] as? Bool, false)
        XCTAssertEqual(
            info["CFBundleIdentifier"] as? String,
            ParallelRobloxLauncher.parallelBundleIdentifier
        )
        XCTAssertEqual(info["RAMSourceBundleVersion"] as? String, "7330989")
        XCTAssertEqual(
            info["RAMPreparationVersion"] as? Int,
            ParallelRobloxLauncher.preparationVersion
        )
    }

    func testManagedClientSettingsDisableMenuBarAndDesktopNotifications() {
        XCTAssertEqual(
            ParallelRobloxLauncher.managedClientSettings,
            [
                "DFFlagEnableMacDesktopNotifications2": false,
                "FFlagEnableMacDesktopNotifications": false,
                "FFlagEnableMacMenuBar": false,
                "FFlagEnableMacMenuBar9": false
            ]
        )
    }

    func testUnmodifiedParallelModeDescribesExactOriginalSignatureCopies() {
        XCTAssertEqual(RobloxLaunchMode.unmodifiedParallel.title, "Unmodified Parallel")
        XCTAssertTrue(RobloxLaunchMode.unmodifiedParallel.detail.contains("byte-identical"))
        XCTAssertTrue(RobloxLaunchMode.unmodifiedParallel.detail.contains("original signature"))
    }

    func testLiveConcurrentUnmodifiedLaunchWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RAM_RUN_UNMODIFIED_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RAM_RUN_UNMODIFIED_INTEGRATION=1 to run the exact-copy integration test.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-unmodified-integration-\(UUID().uuidString)", isDirectory: true)
        let launcher = ParallelRobloxLauncher(instancesRoot: root)
        let accountIDs = [UUID(), UUID()]
        addTeardownBlock {
            for accountID in accountIDs {
                _ = await launcher.stop(accountID: accountID)
            }
            try? FileManager.default.removeItem(at: root)
        }
        let invalidTicketURL = try builder.makeURL(
            ticket: "invalid-unmodified-integration-ticket",
            placeID: 920587237,
            trackerID: "123456789012",
            launchTime: 1
        )

        let instances = try await withThrowingTaskGroup(of: ParallelRobloxInstance.self) { group in
            for accountID in accountIDs {
                group.addTask {
                    try await launcher.launch(
                        invalidTicketURL,
                        for: accountID,
                        mode: .unmodifiedParallel
                    )
                }
            }
            var launched: [ParallelRobloxInstance] = []
            for try await instance in group { launched.append(instance) }
            return launched
        }

        XCTAssertEqual(instances.count, 2)
        XCTAssertEqual(Set(instances.map(\.processIdentifier)).count, 2)
        let runningAfterLaunch = await launcher.runningAccountIDs(from: accountIDs)
        XCTAssertEqual(runningAfterLaunch, Set(accountIDs))
        for instance in instances {
            XCTAssertEqual(kill(instance.processIdentifier, 0), 0)
            XCTAssertTrue(instance.applicationURL.path.contains("/Unmodified/Roblox.app"))
            XCTAssertNoThrow(try runCommand(
                "/usr/bin/diff",
                ["-qr", ParallelRobloxLauncher.officialApplicationURL.path, instance.applicationURL.path]
            ))
            XCTAssertNoThrow(try runCommand(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", instance.applicationURL.path]
            ))
            let signature = try runCommand(
                "/usr/bin/codesign",
                ["-d", "--verbose=4", instance.applicationURL.path]
            )
            XCTAssertTrue(signature.contains("TeamIdentifier=\(ParallelRobloxLauncher.officialTeamIdentifier)"))
        }

        for accountID in accountIDs {
            let stopped = await launcher.stop(accountID: accountID)
            XCTAssertTrue(stopped)
        }
        let runningAfterStop = await launcher.runningAccountIDs(from: accountIDs)
        XCTAssertTrue(runningAfterStop.isEmpty)
    }

    func testLiveConcurrentParallelCopyLaunchWhenEnabled() async throws {
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

        let instances = try await withThrowingTaskGroup(of: ParallelRobloxInstance.self) { group in
            for accountID in accountIDs {
                group.addTask {
                    try await launcher.launch(
                        invalidTicketURL,
                        for: accountID,
                        mode: .modifiedParallel
                    )
                }
            }
            var launched: [ParallelRobloxInstance] = []
            for try await instance in group { launched.append(instance) }
            return launched
        }
        XCTAssertEqual(instances.count, 2)
        XCTAssertTrue(instances.allSatisfy { $0.processIdentifier > 0 })
        XCTAssertEqual(Set(instances.map(\.processIdentifier)).count, 2)
        let runningAfterLaunch = await launcher.runningAccountIDs(from: accountIDs)
        XCTAssertEqual(runningAfterLaunch, Set(accountIDs))
        for instance in instances {
            XCTAssertEqual(kill(instance.processIdentifier, 0), 0)
        }

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

@discardableResult
private func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "RobloxLauncherTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output]
        )
    }
    return output
}

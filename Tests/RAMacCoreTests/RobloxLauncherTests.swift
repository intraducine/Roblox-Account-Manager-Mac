import Darwin
import Foundation
import XCTest
@testable import RAMacCore

final class RobloxLauncherTests: XCTestCase {
    private let builder = RobloxLaunchURLBuilder()

    func testOfficialSignatureRequirementUsesCodesignInlineArgument() {
        let appURL = URL(fileURLWithPath: "/Applications/Roblox.app", isDirectory: true)
        let arguments = ParallelRobloxLauncher.officialVerificationArguments(for: appURL)

        XCTAssertTrue(arguments.contains("-R=\(ParallelRobloxLauncher.officialCodeRequirement)"))
        XCTAssertFalse(arguments.contains("-R"))
        XCTAssertEqual(arguments.last, appURL.path)
    }

    func testCommandOutputLargerThanAPipeBufferDoesNotDeadlock() throws {
        let output = try ParallelRobloxLauncher.collectCommandOutput(
            executable: URL(fileURLWithPath: "/usr/bin/jot"),
            arguments: ["50000"]
        )

        XCTAssertTrue(output.hasPrefix("1\n2\n3\n"))
        XCTAssertTrue(output.hasSuffix("50000\n"))
        XCTAssertGreaterThan(output.utf8.count, 64 * 1024)
    }

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

    func testAppLaunchURLSelectsAccountWithoutJoiningAGame() throws {
        let url = try builder.makeAppURL(ticket: "account-ticket")

        XCTAssertEqual(url.scheme, "roblox-player")
        XCTAssertTrue(url.absoluteString.contains("launchmode:app"))
        XCTAssertTrue(url.absoluteString.contains("gameinfo:account-ticket"))
        XCTAssertFalse(url.absoluteString.contains("placelauncherurl"))
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

    func testFollowUserRequestUsesTheFriendUserID() throws {
        let follow = try builder.makeURL(
            ticket: "ticket",
            placeID: 1818,
            target: .followUser(42),
            trackerID: "123456789012",
            launchTime: 1
        )

        XCTAssertTrue(follow.absoluteString.contains("RequestFollowUser"))
        XCTAssertTrue(follow.absoluteString.contains("userId%3D42"))
        XCTAssertFalse(follow.absoluteString.contains("RequestGameJob"))
    }

    func testWebsitePlayLinkParsesAutomaticAndSpecificServerTargets() throws {
        let automaticURL = try builder.makeURL(
            ticket: "page-ticket-that-must-not-be-reused",
            placeID: 1818,
            trackerID: "123456789012",
            launchTime: 1
        )
        let jobURL = try builder.makeURL(
            ticket: "another-page-ticket",
            placeID: 1818,
            target: .job("11111111-2222-3333-4444-555555555555"),
            trackerID: "123456789012",
            launchTime: 1
        )

        XCTAssertEqual(
            RobloxWebLaunchRequestParser.parse(automaticURL),
            RobloxWebLaunchRequest(placeID: 1818, server: .automatic)
        )
        XCTAssertEqual(
            RobloxWebLaunchRequestParser.parse(jobURL),
            RobloxWebLaunchRequest(
                placeID: 1818,
                server: .manualJob("11111111-2222-3333-4444-555555555555")
            )
        )
    }

    func testWebsitePrivatePlayLinkKeepsOnlyTheReusableLinkCode() throws {
        let pageURL = try builder.makeURL(
            ticket: "page-ticket",
            placeID: 1818,
            target: .privateServer(accessCode: "page-access-code", linkCode: "private-link-code"),
            trackerID: "123456789012",
            launchTime: 1
        )
        let request = try XCTUnwrap(RobloxWebLaunchRequestParser.parse(pageURL))

        XCTAssertEqual(request.placeID, 1818)
        guard case .privateLink(let link) = request.server else {
            return XCTFail("Expected a private link target")
        }
        XCTAssertEqual(RobloxLaunchURLBuilder.privateLinkCode(from: link), "private-link-code")
        XCTAssertFalse(link.contains("page-access-code"))
        XCTAssertFalse(link.contains("page-ticket"))
    }

    func testWebsitePlayParserAcceptsOfficialDirectLinkAndRejectsAnotherLauncherHost() throws {
        let direct = try XCTUnwrap(URL(string: "roblox://placeId=1818&launchData=ignored"))
        XCTAssertEqual(
            RobloxWebLaunchRequestParser.parse(direct),
            RobloxWebLaunchRequest(placeID: 1818, server: .automatic)
        )

        let unsafeLauncher = "https://example.com/game/PlaceLauncher.ashx?request=RequestGame&placeId=1818"
        let encoded = try XCTUnwrap(
            unsafeLauncher.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        )
        let unsafeURL = try XCTUnwrap(URL(string: "roblox-player:1+launchmode:play+placelauncherurl:\(encoded)"))
        XCTAssertNil(RobloxWebLaunchRequestParser.parse(unsafeURL))
    }

    func testWebsiteCurrentShareLinkBecomesAnAccountResolvedPrivateLaunch() throws {
        let url = try XCTUnwrap(
            URL(string: "roblox://navigation/share_links?code=current-share-code&type=Server")
        )
        let request = try XCTUnwrap(RobloxWebLaunchRequestParser.parse(url))

        XCTAssertEqual(request.placeID, 0)
        guard case .privateLink(let link) = request.server else {
            return XCTFail("Expected a private share link")
        }
        XCTAssertEqual(RobloxLaunchURLBuilder.privateShareCode(from: link), "current-share-code")
    }

    func testWebsiteDirectPrivateLaunchKeepsLinkCodeAndDropsAccessCode() throws {
        let url = try XCTUnwrap(URL(
            string: "roblox://experiences/start?placeId=1818&accessCode=page-access&linkCode=private-link"
        ))
        let request = try XCTUnwrap(RobloxWebLaunchRequestParser.parse(url))

        XCTAssertEqual(request.placeID, 1818)
        guard case .privateLink(let link) = request.server else {
            return XCTFail("Expected a private link target")
        }
        XCTAssertEqual(RobloxLaunchURLBuilder.privateLinkCode(from: link), "private-link")
        XCTAssertFalse(link.contains("page-access"))
    }

    func testWebsiteReservedServerWithoutReusableLinkCodeIsRejected() throws {
        let url = try XCTUnwrap(URL(
            string: "roblox://experiences/start?placeId=1818&reservedServerAccessCode=one-use-secret"
        ))

        XCTAssertNil(RobloxWebLaunchRequestParser.parse(url))
    }

    func testWebsitePlayParserAcceptsCurrentRobloxWebsiteLauncherHost() throws {
        let launcher = "https://www.roblox.com/Game/PlaceLauncher.ashx?request=RequestGame&placeId=1818&isPlayTogetherGame=false"
        let encoded = try XCTUnwrap(
            launcher.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        )
        let url = try XCTUnwrap(
            URL(string: "roblox-player:1+launchmode:play+gameinfo:page-ticket+placelauncherurl:\(encoded)")
        )

        XCTAssertEqual(
            RobloxWebLaunchRequestParser.parse(url),
            RobloxWebLaunchRequest(placeID: 1818, server: .automatic)
        )
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

    func testServerSelectionDoesNotPersistDiscoveredJobIDs() {
        let jobID = "11111111-2222-3333-4444-555555555555"
        XCTAssertEqual(
            RobloxServerSelection.publicInstance(jobID: jobID, playing: 2, maxPlayers: 8).persistedValue,
            ""
        )
        XCTAssertEqual(
            RobloxServerSelection.player(username: "builder", userID: 42, jobID: jobID).persistedValue,
            ""
        )
        XCTAssertEqual(RobloxServerSelection.manualJob(jobID).persistedValue, "")
    }

    func testModernPrivateShareLinkIsRecognizedSeparately() {
        let link = "https://www.roblox.com/share?code=abc123&type=Server"
        XCTAssertEqual(RobloxLaunchURLBuilder.privateShareCode(from: link), "abc123")
        XCTAssertNil(RobloxLaunchURLBuilder.privateLinkCode(from: link))
        XCTAssertEqual(RobloxServerSelection.savedValue(link), .privateLink(link))
        XCTAssertEqual(
            RobloxLaunchURLBuilder.privateShareCode(
                from: "https://www.roblox.com/share-links?type=Server&code=abc123"
            ),
            "abc123"
        )
    }

    func testPrivateServerLinksRejectLookAlikeDomains() {
        XCTAssertNil(RobloxLaunchURLBuilder.privateShareCode(
            from: "https://evilroblox.com/share?code=abc123&type=Server"
        ))
        XCTAssertNil(RobloxLaunchURLBuilder.privateLinkCode(
            from: "https://evilroblox.com/games/123?privateServerLinkCode=abc123"
        ))
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

    func testEachManagedAccountGetsASeparateRobloxHome() {
        let root = URL(fileURLWithPath: "/tmp/ram-instance-root", isDirectory: true)
        let first = UUID()
        let second = UUID()

        let firstHome = ParallelRobloxLauncher.isolatedHomeURL(instancesRoot: root, accountID: first)
        let secondHome = ParallelRobloxLauncher.isolatedHomeURL(instancesRoot: root, accountID: second)

        XCTAssertNotEqual(firstHome, secondHome)
        XCTAssertTrue(firstHome.path.hasSuffix("/\(first.uuidString)/Home"))
        XCTAssertTrue(secondHome.path.hasSuffix("/\(second.uuidString)/Home"))
    }

    func testRobloxChildEnvironmentDoesNotInheritParentSecrets() {
        let home = URL(fileURLWithPath: "/tmp/ram-test-home", isDirectory: true)
        let temporary = home.appendingPathComponent("tmp", isDirectory: true)
        let environment = ParallelRobloxLauncher.sanitizedChildEnvironment(
            parent: [
                "LANG": "en_US.UTF-8",
                "GITHUB_TOKEN": "must-not-cross",
                "SSH_AUTH_SOCK": "/tmp/private-agent",
                "HTTPS_PROXY": "https://secret.example"
            ],
            homeURL: home,
            temporaryURL: temporary
        )

        XCTAssertEqual(environment["HOME"], home.path)
        XCTAssertEqual(environment["CFFIXED_USER_HOME"], home.path)
        XCTAssertEqual(environment["TMPDIR"], temporary.path + "/")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertNil(environment["GITHUB_TOKEN"])
        XCTAssertNil(environment["SSH_AUTH_SOCK"])
        XCTAssertNil(environment["HTTPS_PROXY"])
    }

    func testParallelInfoPlistPatchPreservesRobloxMetadata() throws {
        let accountID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let source: [String: Any] = [
            "CFBundleIdentifier": "com.roblox.RobloxPlayer",
            "CFBundleExecutable": "RobloxPlayer",
            "CFBundleVersion": "7330989",
            "LSMultipleInstancesProhibited": true,
            "NSMicrophoneUsageDescription": "Roblox microphone description"
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
        XCTAssertEqual(
            info["NSMicrophoneUsageDescription"] as? String,
            "Roblox microphone description"
        )
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

    func testManagerBundleDeclaresPrivacyUsageForManagedRobloxClients() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot.appendingPathComponent("packaging/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let info = try XCTUnwrap(object as? [String: Any])

        for key in [
            "NSMicrophoneUsageDescription",
            "NSCameraUsageDescription",
            "NSLocalNetworkUsageDescription"
        ] {
            let description = try XCTUnwrap(info[key] as? String, "Missing \(key)")
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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

    func testIsolatedEnvironmentHasItsOwnUsableDefaultKeychain() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-keychain-environment-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let accountID = UUID()
        let launcher = ParallelRobloxLauncher(instancesRoot: root)

        let environment = try await launcher.prepareIsolatedEnvironment(for: accountID)
        let home = try XCTUnwrap(environment["HOME"])
        let keychain = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Keychains/login.keychain-db")

        XCTAssertTrue(FileManager.default.fileExists(atPath: keychain.path))
        XCTAssertNotEqual(
            keychain.standardizedFileURL.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Keychains/login.keychain-db")
                .standardizedFileURL.path
        )

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        probe.arguments = [
            "add-generic-password",
            "-a", "Roblox test",
            "-s", "https://www.roblox.com/:SharedROBLOSECURITYForStudio",
            "-w", "test-value"
        ]
        probe.environment = environment
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        try probe.run()
        probe.waitUntilExit()
        XCTAssertEqual(probe.terminationStatus, 0)
    }

    func testBatchStopClosesSeveralRecordedProcessesPromptly() async throws {
        struct TestProcessRecord: Codable {
            let processIdentifier: Int32
            let applicationPath: String
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-batch-stop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = ParallelRobloxLauncher(instancesRoot: root)
        let accountIDs = [UUID(), UUID(), UUID()]
        var processes: [Process] = []
        defer {
            for process in processes where process.isRunning { process.terminate() }
        }

        for accountID in accountIDs {
            let accountRoot = root.appendingPathComponent(accountID.uuidString, isDirectory: true)
            let app = accountRoot.appendingPathComponent("Unmodified/Roblox.app", isDirectory: true)
            let executable = app.appendingPathComponent("Contents/MacOS/RobloxPlayer")
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: executable.path)

            let process = Process()
            process.executableURL = executable
            process.arguments = ["60"]
            try process.run()
            processes.append(process)
            XCTAssertTrue(
                waitForExecutablePath(
                    processIdentifier: process.processIdentifier,
                    expectedPath: executable.path
                )
            )
            let record = TestProcessRecord(
                processIdentifier: process.processIdentifier,
                applicationPath: app.standardizedFileURL.path
            )
            try JSONEncoder().encode(record).write(
                to: accountRoot.appendingPathComponent("Process.json"),
                options: .atomic
            )
        }

        let startedAt = Date()
        let stopped = await launcher.stop(accountIDs: accountIDs)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(stopped, Set(accountIDs))
        XCTAssertLessThan(elapsed, 5)
        for process in processes { process.waitUntilExit() }
        XCTAssertTrue(processes.allSatisfy { !$0.isRunning })
    }

    private func waitForExecutablePath(processIdentifier: Int32, expectedPath: String) -> Bool {
        let canonicalExpectedPath = URL(fileURLWithPath: expectedPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        for _ in 0..<100 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            if proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count)) > 0 {
                let currentPath = URL(fileURLWithPath: String(cString: buffer))
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
                    .path
                if currentPath == canonicalExpectedPath { return true }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
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

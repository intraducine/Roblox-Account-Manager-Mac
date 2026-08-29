import Foundation
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class AccountStoreBatchTests: XCTestCase {
    func testStartupChecksEverySavedAccountOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-startup-health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = [
            ManagedAccount(userID: 1, username: "first", displayName: "First"),
            ManagedAccount(userID: 2, username: "second", displayName: "Second")
        ]
        try repository.save(accounts)
        let checker = CountingHealthChecker()
        let store = AccountStore(
            repository: repository,
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            healthChecker: checker
        )

        await store.checkAccountsOnStartup()
        await store.checkAccountsOnStartup()

        let checkedAccountIDs = await checker.checkedAccountIDs()
        let checkCount = await checker.checkCount()
        XCTAssertEqual(checkedAccountIDs, Set(accounts.map(\.id)))
        XCTAssertEqual(checkCount, accounts.count)
        XCTAssertTrue(accounts.allSatisfy { store.accountHealth[$0.id]?.isReady == true })
    }

    func testLaunchModeDefaultsToUnmodifiedAndFallbackIsSessionOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-mode-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = BatchMockLauncher(failingAccountID: nil)

        let initial = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher
        )
        XCTAssertEqual(initial.launchMode, .unmodifiedParallel)

        initial.setLaunchMode(.modifiedParallel)
        XCTAssertEqual(initial.launchMode, .modifiedParallel)
        let reloaded = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher
        )
        XCTAssertEqual(reloaded.launchMode, .unmodifiedParallel)
    }

    func testLaunchSettingsAreRememberedAndUsedForEverySelectedAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-settings-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "ram-settings-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = [
            ManagedAccount(userID: 1, username: "first", displayName: "First"),
            ManagedAccount(userID: 2, username: "second", displayName: "Second")
        ]
        try repository.save(accounts)
        let vault = MemoryVault()
        for account in accounts { try vault.save("cookie", for: account.id) }
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let expected = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 2,
            overridesVolume: true,
            volume: 0.15
        )
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: launcher,
            settingsDefaults: defaults
        )
        store.launchSettings = expected
        for account in accounts { store.toggleBatchSelection(account) }

        await store.launchSelectedApps(skipHealthPreflight: true)

        let attemptedSettings = await launcher.attemptedLaunchSettings()
        XCTAssertEqual(attemptedSettings, [expected, expected])
        let reloaded = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            settingsDefaults: defaults
        )
        XCTAssertEqual(reloaded.launchSettings, expected)
    }

    func testBatchLaunchCanTemporarilyOverrideLaunchDefaults() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let defaults = RobloxLaunchSettings(graphics: .automatic)
        let override = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 8,
            overridesVolume: true,
            volume: 0.75
        )
        fixture.store.launchSettings = defaults
        fixture.store.batchLaunchSettingsOverride = override
        for account in fixture.accounts { fixture.store.toggleBatchSelection(account) }

        await fixture.store.launchSelectedApps(skipHealthPreflight: true)

        let attemptedSettings = await fixture.launcher.attemptedLaunchSettings()
        XCTAssertEqual(attemptedSettings, Array(repeating: override, count: fixture.accounts.count))
        XCTAssertEqual(fixture.store.launchSettings, defaults)
        XCTAssertNil(fixture.store.batchLaunchSettingsOverride)
    }

    func testDamagedLaunchSetsAreReportedWithoutChangingTheFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-damaged-launch-sets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let launchSetURL = directory.appendingPathComponent("LaunchSets.json")
        let damagedData = Data("not json".utf8)
        try damagedData.write(to: launchSetURL)

        let store = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        XCTAssertTrue(store.launchSets.isEmpty)
        XCTAssertEqual(store.notice?.title, "Some saved data needed recovery")
        XCTAssertTrue(store.notice?.message.contains("Launch Sets could not load") == true)
        XCTAssertEqual(try Data(contentsOf: launchSetURL), damagedData)
    }

    func testDamagedLaunchSetsRestoreTheLastValidBackupAndWarnTheUser() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-recovered-launch-sets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launchSets = LaunchSetRepository(fileName: "LaunchSets.json", dataDirectory: directory)
        let first = LaunchSet(name: "First", placeID: 100)
        try launchSets.save([first])
        try launchSets.save([LaunchSet(name: "Second", placeID: 200)])
        try Data("not json".utf8).write(to: directory.appendingPathComponent("LaunchSets.json"))

        let store = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        XCTAssertEqual(store.launchSets, [first])
        XCTAssertTrue(store.notice?.message.contains("Launch Sets was recovered") == true)
        XCTAssertEqual(try launchSets.load(), [first])
    }

    func testGroupSelectionTogglesEveryEligibleAccount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        XCTAssertEqual(fixture.store.batchSelectedIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertTrue(fixture.store.isBatchGroupSelected("Wave"))

        fixture.store.toggleBatchGroup("Wave")
        XCTAssertTrue(fixture.store.batchSelectedIDs.isEmpty)
        XCTAssertFalse(fixture.store.isBatchGroupSelected("Wave"))
    }

    func testAccountCanJoinSeveralGroupsAndEachGroupCanSelectIt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = fixture.store.createGroup("Favorites", addingTo: fixture.accounts[0].id)
        let updated = try XCTUnwrap(fixture.store.accounts.first(where: { $0.id == fixture.accounts[0].id }))
        XCTAssertTrue(updated.belongs(to: "Wave"))
        XCTAssertTrue(updated.belongs(to: "Favorites"))

        fixture.store.toggleBatchGroup("Favorites")
        XCTAssertEqual(fixture.store.batchSelectedIDs, [fixture.accounts[0].id])
    }

    func testDeletingGroupKeepsAccountsAndRemovesOnlyMembershipReferences() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = fixture.store.createGroup("Favorites", addingTo: fixture.accounts[0].id)
        fixture.store.saveLaunchSet(LaunchSet(
            name: "Favorites Set",
            groupNames: ["Favorites", "Wave"],
            placeID: 12345
        ))

        fixture.store.deleteGroup("Favorites")

        XCTAssertEqual(fixture.store.accounts.count, fixture.accounts.count)
        XCTAssertFalse(fixture.store.groupNames.contains("Favorites"))
        XCTAssertTrue(fixture.store.accounts.allSatisfy { !$0.belongs(to: "Favorites") })
        XCTAssertEqual(fixture.store.launchSets.first?.groupNames, ["Wave"])
        XCTAssertEqual(try fixture.repository.load().count, fixture.accounts.count)
        XCTAssertFalse(try fixture.repository.loadGroups().contains("Favorites"))
    }

    func testIndividualBatchSelectionSelectsAndDeselectsOnlyTheTargetAccount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchSelection(fixture.accounts[1])
        XCTAssertEqual(fixture.store.batchSelectedIDs, [fixture.accounts[1].id])

        fixture.store.toggleBatchSelection(fixture.accounts[1])
        XCTAssertTrue(fixture.store.batchSelectedIDs.isEmpty)
    }

    func testBatchLaunchStartsRequestsTogetherAndKeepsOnlyFailuresSelected() async throws {
        let fixture = try makeFixture(failingIndex: 1)
        let jobID = "11111111-2222-3333-4444-555555555555"
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        fixture.store.batchWindowArrangement = .unchanged
        await fixture.store.launchBatch(placeText: "12345", serverText: jobID)

        let maximumConcurrentRequests = await fixture.api.maximumConcurrentTicketRequests()
        let attemptedAccountIDs = await fixture.launcher.attemptedAccountIDs()
        let attemptedModes = await fixture.launcher.attemptedModes()
        let runningAccountIDs = await fixture.launcher.runningAccountIDs(from: fixture.accounts.map(\.id))
        XCTAssertEqual(maximumConcurrentRequests, 3)
        XCTAssertEqual(attemptedAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(attemptedModes, [.unmodifiedParallel])
        XCTAssertEqual(runningAccountIDs, Set([fixture.accounts[0].id, fixture.accounts[2].id]))
        XCTAssertEqual(fixture.store.batchSelectedIDs, Set([fixture.accounts[1].id]))
        XCTAssertEqual(fixture.store.batchStatus, "2 started, 1 failed")
        XCTAssertEqual(fixture.store.launchStatus, "2 running, 1 failed")
        XCTAssertEqual(fixture.store.notice?.title, "1 account did not start")
        XCTAssertEqual(fixture.store.batchWindowArrangement, .unchanged)
        guard case .failed = fixture.store.batchStates[fixture.accounts[1].id] else {
            return XCTFail("The failed account must stay marked for retry.")
        }

        let saved = try fixture.repository.load()
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[0].id })?.savedPlaceID, "12345")
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[0].id })?.savedServer, "")
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[1].id })?.savedPlaceID, "")
    }

    func testBatchLaunchPlacesOnlyAssignedProfilesUsingTheirRobloxProcessIDs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-window-layout-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<3).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "layout_\(index + 1)",
                displayName: "Layout \(index + 1)",
                group: "Layout"
            )
        }
        try repository.save(accounts)
        let vault = MemoryVault()
        for account in accounts { try vault.save("cookie-\(account.userID)", for: account.id) }
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let windowPlacer = BatchRecordingWindowPlacer()
        let display = batchTestDisplay
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [display],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: windowPlacer,
            permissionManager: BatchAccessibilityPermissionManager()
        )
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: launcher,
            windowLayout: windowLayout
        )
        windowLayout.assign(accountID: accounts[0].id, to: display, region: .topLeft)
        windowLayout.assign(accountID: accounts[1].id, to: display, region: .right)

        store.toggleBatchGroup("Layout")
        await store.launchBatch(placeText: "12345", serverText: "")

        let processIdentifiers = await launcher.processIdentifiersByAccount()
        let placements = await windowPlacer.recordedRequests()
        XCTAssertEqual(Set(placements.map(\.processIdentifier)), Set([
            try XCTUnwrap(processIdentifiers[accounts[0].id]),
            try XCTUnwrap(processIdentifiers[accounts[1].id])
        ]))
        XCTAssertFalse(placements.contains { $0.processIdentifier == processIdentifiers[accounts[2].id] })
    }

    func testBatchPlacementStartsBeforeTheSlowestRobloxLaunchFinishes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-window-layout-pipeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<2).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "pipeline_\(index + 1)",
                displayName: "Pipeline \(index + 1)",
                group: "Pipeline"
            )
        }
        try repository.save(accounts)
        let vault = MemoryVault()
        for account in accounts { try vault.save("cookie-\(account.userID)", for: account.id) }
        let launcher = BatchMockLauncher(
            failingAccountID: nil,
            blockedAccountIDs: [accounts[1].id]
        )
        let firstPlacement = expectation(description: "The first Roblox window is placed")
        let windowPlacer = BatchRecordingWindowPlacer(onPlace: { firstPlacement.fulfill() })
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [batchTestDisplay],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: windowPlacer,
            permissionManager: BatchAccessibilityPermissionManager()
        )
        windowLayout.assign(accountID: accounts[0].id, to: batchTestDisplay, region: .left)
        windowLayout.assign(accountID: accounts[1].id, to: batchTestDisplay, region: .right)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: launcher,
            windowLayout: windowLayout
        )
        store.toggleBatchGroup("Pipeline")

        let launchTask = Task {
            await store.launchBatch(
                placeText: "12345",
                server: .automatic,
                skipHealthPreflight: true
            )
        }
        await fulfillment(of: [firstPlacement], timeout: 2)

        let earlyRequests = await windowPlacer.recordedRequests()
        XCTAssertEqual(earlyRequests.count, 1)

        await launcher.releaseBlockedLaunch(for: accounts[1].id)
        await launchTask.value
        let finalRequests = await windowPlacer.recordedRequests()
        XCTAssertEqual(finalRequests.count, 2)
    }

    func testBatchPlacementNoticeNamesEveryAccountThatNeedsAttention() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-window-layout-errors-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<2).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "layout_error_\(index + 1)",
                displayName: "Layout Error \(index + 1)",
                group: "Layout Errors"
            )
        }
        try repository.save(accounts)
        let vault = MemoryVault()
        for account in accounts { try vault.save("cookie-\(account.userID)", for: account.id) }
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [batchTestDisplay],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: BatchRecordingWindowPlacer(
                result: .failed("The game window was still starting.")
            ),
            permissionManager: BatchAccessibilityPermissionManager()
        )
        windowLayout.assign(accountID: accounts[0].id, to: batchTestDisplay, region: .left)
        windowLayout.assign(accountID: accounts[1].id, to: batchTestDisplay, region: .right)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            windowLayout: windowLayout
        )
        store.toggleBatchGroup("Layout Errors")

        await store.launchBatch(
            placeText: "12345",
            server: .automatic,
            skipHealthPreflight: true
        )

        XCTAssertEqual(store.notice?.title, "2 Roblox windows need attention")
        XCTAssertTrue(store.notice?.message.contains("@layout_error_1") == true)
        XCTAssertTrue(store.notice?.message.contains("@layout_error_2") == true)
    }

    func testFirstWindowArrangementLaunchExplainsMissingAccessibilityPermission() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-first-window-layout-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(
            userID: 1,
            username: "first_window_layout",
            displayName: "First Window Layout"
        )
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("cookie", for: account.id)
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [batchTestDisplay],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: BatchRecordingWindowPlacer(),
            permissionManager: BatchAccessibilityPermissionManager(trusted: false)
        )
        windowLayout.assign(accountID: account.id, to: batchTestDisplay, region: .left)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            windowLayout: windowLayout
        )
        store.toggleBatchSelection(account)

        await store.launchBatch(
            placeText: "12345",
            server: .automatic,
            skipHealthPreflight: true
        )

        XCTAssertEqual(store.runningAccountIDs, Set([account.id]))
        XCTAssertEqual(store.notice?.title, "Roblox opened without its saved layout")
        XCTAssertEqual(
            store.notice?.message,
            "@first_window_layout: Allow Window Control in System Settings so the app can arrange Roblox windows."
        )
    }

    func testBatchLaunchUsesTemporaryCustomArrangementAndResetsAfterSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-custom-window-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<3).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "custom_layout_\(index + 1)",
                displayName: "Custom Layout \(index + 1)",
                group: "Layout"
            )
        }
        try repository.save(accounts)
        let vault = MemoryVault()
        for account in accounts { try vault.save("cookie-\(account.userID)", for: account.id) }
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let windowPlacer = BatchRecordingWindowPlacer()
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [batchTestDisplay],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: windowPlacer,
            permissionManager: BatchAccessibilityPermissionManager()
        )
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: launcher,
            windowLayout: windowLayout
        )
        store.toggleBatchGroup("Layout")
        store.batchWindowArrangement = .custom([
            WindowLayoutAssignment(
                accountID: accounts[2].id,
                displayID: batchTestDisplay.id,
                displayName: batchTestDisplay.name,
                displayPixelWidth: batchTestDisplay.pixelWidth,
                displayPixelHeight: batchTestDisplay.pixelHeight,
                region: .bottomRight
            )
        ])

        await store.launchBatch(placeText: "12345", serverText: "")

        let launchedProcessIdentifiers = await launcher.processIdentifiersByAccount()
        let placements = await windowPlacer.recordedRequests()
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements.first?.processIdentifier, launchedProcessIdentifiers[accounts[2].id])
        XCTAssertEqual(placements.first?.request.region, .bottomRight)
        XCTAssertNil(windowLayout.assignment(for: accounts[2].id))
        XCTAssertEqual(store.batchWindowArrangement, .savedPlacements)
    }

    func testBatchLaunchCanLeaveSavedPlacementsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-unchanged-window-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(
            userID: 1,
            username: "unchanged_layout",
            displayName: "Unchanged Layout"
        )
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("cookie", for: account.id)
        let windowPlacer = BatchRecordingWindowPlacer()
        let windowLayout = WindowLayoutController(
            repository: BatchMemoryWindowLayoutRepository(),
            displayProvider: BatchStaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(
                    displays: [batchTestDisplay],
                    accessibilityReferenceTop: 1000
                )
            ),
            placer: windowPlacer,
            permissionManager: BatchAccessibilityPermissionManager()
        )
        windowLayout.assign(accountID: account.id, to: batchTestDisplay, region: .left)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            windowLayout: windowLayout
        )
        store.toggleBatchSelection(account)
        store.batchWindowArrangement = .unchanged

        await store.launchBatch(placeText: "12345", serverText: "")

        let placementRequests = await windowPlacer.recordedRequests()
        XCTAssertTrue(placementRequests.isEmpty)
        XCTAssertEqual(windowLayout.assignment(for: account.id)?.region, .left)
    }

    func testStopAllStopsEveryRunningAccount() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchBatch(placeText: "12345", serverText: "")
        XCTAssertEqual(fixture.store.runningAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(fixture.store.launchStatus, "Running 3 accounts with the recommended method")

        await fixture.store.stopAll()

        let batchStopRequestCount = await fixture.launcher.batchStopRequestCount()
        XCTAssertTrue(fixture.store.runningAccountIDs.isEmpty)
        XCTAssertEqual(batchStopRequestCount, 1)
        XCTAssertEqual(fixture.store.launchStatus, "Stopped all Roblox clients")
        XCTAssertEqual(fixture.store.batchStatus, "All Roblox clients stopped")
    }

    func testPublicServerPagesAreCachedToProtectRobloxRateLimit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let first = try await fixture.store.publicServerPage(placeID: 1818)
        let second = try await fixture.store.publicServerPage(placeID: 1818)
        let cachedRequestCount = await fixture.api.publicServerRequestCount()
        _ = try await fixture.store.publicServerPage(placeID: 1818, forceRefresh: true)
        let refreshedRequestCount = await fixture.api.publicServerRequestCount()

        XCTAssertEqual(first.page, second.page)
        XCTAssertEqual(cachedRequestCount, 1)
        XCTAssertEqual(refreshedRequestCount, 2)
    }

    func testRecentExperienceStoresResolvedGameNameAndIcon() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-experience-metadata-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let experienceRepository = ExperienceLibraryRepository(
            fileName: "Experiences.json",
            dataDirectory: directory
        )
        try experienceRepository.save([ExperienceRecord(placeID: 1818, launchCount: 1)])
        let store = AccountStore(
            repository: repository,
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            experienceRepository: experienceRepository,
            experienceMetadataProvider: ExperienceMetadataMock()
        )

        await store.refreshExperienceMetadata()

        XCTAssertEqual(store.experiences.first?.experienceName, "Classic: Crossroads")
        XCTAssertEqual(store.experiences.first?.thumbnailURLString, "https://tr.rbxcdn.com/crossroads.png")
        let saved = try experienceRepository.load()
        XCTAssertEqual(saved.first?.experienceName, "Classic: Crossroads")
        XCTAssertEqual(saved.first?.thumbnailURLString, "https://tr.rbxcdn.com/crossroads.png")
    }

    func testGameLookupRefreshesARecordThatHasNoIcon() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-experience-lookup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let experienceRepository = ExperienceLibraryRepository(
            fileName: "Experiences.json",
            dataDirectory: directory
        )
        try experienceRepository.save([
            ExperienceRecord(placeID: 1818, experienceName: "Saved game without an icon")
        ])
        let store = AccountStore(
            repository: repository,
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil),
            experienceRepository: experienceRepository,
            experienceMetadataProvider: ExperienceMetadataMock()
        )

        let experience = try await store.findExperience(placeID: 1818)

        XCTAssertEqual(experience.experienceName, "Classic: Crossroads")
        XCTAssertEqual(experience.thumbnailURLString, "https://tr.rbxcdn.com/crossroads.png")
    }

    func testJoinablePlayerServerUsesPublicPresence() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try await fixture.store.joinableServer(for: "builderman")

        XCTAssertEqual(result.user.name, "builderman")
        XCTAssertEqual(result.presence.placeId, 1818)
        XCTAssertEqual(result.presence.gameId, "11111111-2222-3333-4444-555555555555")
    }

    func testFriendJoinStartsSourceFirstAndNeverSearchesPublicServers() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let sourceAccount = fixture.accounts[1]
        let jobID = "11111111-2222-3333-4444-555555555555"
        var staleSource = sourceAccount
        staleSource.savedPlaceID = "999"
        staleSource.savedServer = jobID
        fixture.store.update(staleSource)
        var savedPrivateChoice = fixture.accounts[0]
        savedPrivateChoice.savedPlaceID = "888"
        savedPrivateChoice.savedServer = "https://www.roblox.com/games/888?privateServerLinkCode=saved-choice"
        fixture.store.update(savedPrivateChoice)
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "friend",
                displayName: "Friend",
                sourceAccountIDs: [sourceAccount.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: jobID
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )
        let launchOverride = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 4,
            overridesVolume: true,
            volume: 0.3
        )
        await fixture.store.runLaunchSet(LaunchSet(
            name: "Join Friend",
            accountIDs: fixture.accounts.map(\.id),
            placeID: 1818,
            serverStrategy: .joinPlayer,
            launchSettings: launchOverride
        ))

        await fixture.store.launchFriendPlayer(
            player,
            accountIDs: Set(fixture.accounts.map(\.id))
        )

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attempts.first, sourceAccount.id)
        XCTAssertEqual(Set(attempts.dropFirst()), Set(fixture.accounts.map(\.id)).subtracting([sourceAccount.id]))
        let publicServerRequests = await fixture.api.publicServerRequestCount()
        XCTAssertEqual(publicServerRequests, 0)
        XCTAssertEqual(fixture.store.runningAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(fixture.store.batchStatus, "Joined all 3 accounts")
        XCTAssertEqual(fixture.store.launchStatus, "Confirmed 3 accounts in the friend server")
        let attemptedSettings = await fixture.launcher.attemptedLaunchSettings()
        XCTAssertEqual(
            attemptedSettings,
            Array(repeating: launchOverride, count: fixture.accounts.count)
        )
        XCTAssertNil(fixture.store.batchLaunchSettingsOverride)

        let saved = try fixture.repository.load()
        let sourceAfterLaunch = try XCTUnwrap(saved.first(where: { $0.id == sourceAccount.id }))
        XCTAssertEqual(sourceAfterLaunch.savedPlaceID, "999")
        XCTAssertEqual(sourceAfterLaunch.savedServer, "")
        let privateChoiceAfterLaunch = try XCTUnwrap(saved.first(where: { $0.id == savedPrivateChoice.id }))
        XCTAssertEqual(privateChoiceAfterLaunch.savedPlaceID, "888")
        XCTAssertTrue(privateChoiceAfterLaunch.savedServer.hasPrefix("keychain:private-server:"))
        XCTAssertFalse(privateChoiceAfterLaunch.savedServer.contains("saved-choice"))
        let untouchedAfterLaunch = try XCTUnwrap(saved.first(where: { $0.id == fixture.accounts[2].id }))
        XCTAssertEqual(untouchedAfterLaunch.savedPlaceID, "")
        XCTAssertEqual(untouchedAfterLaunch.savedServer, "")
    }

    func testFriendRelayChainsEachAccountThroughAConfirmedFriend() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = fixture.accounts[0]
        let second = fixture.accounts[1]
        let third = fixture.accounts[2]
        let jobID = "11111111-2222-3333-4444-555555555555"
        await fixture.friendRelay.setPlan(FriendRelayPlan(
            sourceAccountIDs: [first.id],
            friendAccountIDs: [
                first.id: [second.id],
                second.id: [first.id, third.id],
                third.id: [second.id]
            ],
            levels: [first.id: 0, second.id: 1, third.id: 2]
        ))
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [first.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: jobID
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(player, accountIDs: Set(fixture.accounts.map(\.id)))

        let attemptedAccountIDs = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attemptedAccountIDs, [first.id, second.id, third.id])
        let urls = await fixture.launcher.attemptedURLs()
        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls[0].absoluteString.contains("RequestFollowUser"))
        XCTAssertTrue(urls[0].absoluteString.contains("userId%3D900"))
        XCTAssertTrue(urls[1].absoluteString.contains("userId%3D1"))
        XCTAssertTrue(urls[2].absoluteString.contains("userId%3D2"))
        XCTAssertEqual(fixture.store.friendRelayStates[first.id], .joined(nil))
        XCTAssertEqual(fixture.store.friendRelayStates[second.id], .joined(first.username))
        XCTAssertEqual(fixture.store.friendRelayStates[third.id], .joined(second.username))
    }

    func testFriendRelayKeepsDirectJobFallbackForAnAccountWithNoPath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = fixture.accounts[0]
        let other = fixture.accounts[1]
        let jobID = "11111111-2222-3333-4444-555555555555"
        await fixture.friendRelay.setPlan(FriendRelayPlan(
            sourceAccountIDs: [source.id],
            friendAccountIDs: [source.id: [], other.id: []],
            levels: [source.id: 0]
        ))
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [source.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: jobID
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(player, accountIDs: [source.id, other.id])

        let urls = await fixture.launcher.attemptedURLs()
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[0].absoluteString.contains("RequestFollowUser"))
        XCTAssertTrue(urls[1].absoluteString.contains("RequestGameJob"))
        XCTAssertEqual(fixture.store.friendRelayStates[other.id], .joined(nil))
    }

    func testFriendRelayReportsEveryAccountWhenAFullServerNeverConfirmsArrival() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let selectedIDs = Set(fixture.accounts.map(\.id))
        let launchOverride = RobloxLaunchSettings(graphics: .automatic, overridesVolume: true, volume: 0.2)
        fixture.store.batchLaunchSettingsOverride = launchOverride
        for account in fixture.accounts {
            await fixture.friendRelay.setArrival(.timedOut, for: account.id)
        }
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [fixture.accounts[0].id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(player, accountIDs: selectedIDs)

        XCTAssertEqual(fixture.store.batchStatus, "0 joined, 3 could not join")
        XCTAssertEqual(fixture.store.batchSelectedIDs, selectedIDs)
        XCTAssertEqual(fixture.store.notice?.title, "Some accounts could not join")
        XCTAssertTrue(fixture.store.runningAccountIDs.isEmpty)
        XCTAssertEqual(fixture.store.batchLaunchSettingsOverride, launchOverride)
        for account in fixture.accounts {
            guard case .failed(let message) = fixture.store.friendRelayStates[account.id] else {
                return XCTFail("Expected @\(account.username) to have a visible relay failure.")
            }
            XCTAssertTrue(message.contains("may be full, restricted, or changed"))
            XCTAssertTrue(message.contains("unconfirmed Roblox window was closed"))
            guard case .failed(let batchMessage) = fixture.store.batchStates[account.id] else {
                return XCTFail("Expected @\(account.username) to remain selected for retry.")
            }
            XCTAssertEqual(batchMessage, message)
        }
    }

    func testFriendRelayUsesAnotherConfirmedSourceWhenTheFirstSourceCannotJoin() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = fixture.accounts[0]
        let second = fixture.accounts[1]
        let third = fixture.accounts[2]
        await fixture.friendRelay.setPlan(FriendRelayPlan(
            sourceAccountIDs: [first.id, second.id],
            friendAccountIDs: [
                first.id: [third.id],
                second.id: [third.id],
                third.id: [first.id, second.id]
            ],
            levels: [first.id: 0, second.id: 0, third.id: 1]
        ))
        await fixture.friendRelay.setArrival(.timedOut, for: first.id)
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [first.id, second.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(
            player,
            accountIDs: Set(fixture.accounts.map(\.id))
        )

        let urls = await fixture.launcher.attemptedURLs()
        XCTAssertEqual(urls.count, 4)
        XCTAssertTrue(urls[2].absoluteString.contains("userId%3D2"))
        XCTAssertTrue(urls[3].absoluteString.contains("RequestGameJob"))
        XCTAssertEqual(fixture.store.friendRelayStates[first.id]?.label, "Could not join")
        XCTAssertEqual(fixture.store.friendRelayStates[second.id], .joined(nil))
        XCTAssertEqual(fixture.store.friendRelayStates[third.id], .joined(second.username))
        XCTAssertEqual(fixture.store.batchStatus, "2 joined, 1 could not join")
    }

    func testFriendRelayContinuesAnIndependentPathAfterOneClientFailsToOpen() async throws {
        let fixture = try makeFixture(failingIndex: 0)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = fixture.accounts[0]
        let second = fixture.accounts[1]
        let third = fixture.accounts[2]
        await fixture.friendRelay.setPlan(FriendRelayPlan(
            sourceAccountIDs: [first.id, second.id],
            friendAccountIDs: [
                first.id: [],
                second.id: [third.id],
                third.id: [second.id]
            ],
            levels: [first.id: 0, second.id: 0, third.id: 1]
        ))
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [first.id, second.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(
            player,
            accountIDs: Set(fixture.accounts.map(\.id))
        )

        XCTAssertEqual(fixture.store.friendRelayStates[first.id]?.label, "Could not join")
        XCTAssertEqual(fixture.store.friendRelayStates[second.id], .joined(nil))
        XCTAssertEqual(fixture.store.friendRelayStates[third.id], .joined(second.username))
        XCTAssertEqual(fixture.store.runningAccountIDs, [second.id, third.id])
        XCTAssertEqual(fixture.store.batchSelectedIDs, [first.id])
        XCTAssertEqual(fixture.store.batchStatus, "2 joined, 1 could not join")
    }

    func testStoppingFriendRelayPreventsTheRemainingAccountsFromStarting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = fixture.accounts[0]
        await fixture.friendRelay.setWaitNanoseconds(300_000_000)
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "target_friend",
                displayName: "Target Friend",
                sourceAccountIDs: [source.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        let relayTask = Task {
            await fixture.store.launchFriendPlayer(player, accountIDs: Set(fixture.accounts.map(\.id)))
        }
        for _ in 0..<100 {
            if await fixture.launcher.attemptedAccountIDs().contains(source.id) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        fixture.store.cancelFriendRelay()
        await relayTask.value

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attempts, [source.id])
        XCTAssertEqual(fixture.store.notice?.title, "Friend relay stopped")
        XCTAssertFalse(fixture.store.isFriendRelayLaunching)
    }

    func testFriendJoinRequiresASelectedSourceAccount() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "friend",
                displayName: "Friend",
                sourceAccountIDs: [fixture.accounts[0].id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(
            player,
            accountIDs: [fixture.accounts[1].id, fixture.accounts[2].id]
        )

        XCTAssertEqual(fixture.store.notice?.title, "Select a friend account")
        let attemptedAccountIDs = await fixture.launcher.attemptedAccountIDs()
        XCTAssertTrue(attemptedAccountIDs.isEmpty)
    }

    func testFriendJoinRejectsAnAccountThatIsAlreadyRunning() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let source = fixture.accounts[0]
        await fixture.store.launch(account: source, placeText: "1818", server: .automatic)
        let attemptsBeforeFriendJoin = await fixture.launcher.orderedAttemptedAccountIDs()
        let player = DiscoveredPlayer(
            candidate: PlayerCandidate(
                userID: 900,
                username: "friend",
                displayName: "Friend",
                sourceAccountIDs: [source.id]
            ),
            presence: PlayerPresenceSnapshot(
                userID: 900,
                presenceType: .inExperience,
                placeID: 1818,
                jobID: "11111111-2222-3333-4444-555555555555"
            ),
            verification: .friendTarget,
            isPubliclyVisible: false
        )

        await fixture.store.launchFriendPlayer(player, accountIDs: [source.id, fixture.accounts[1].id])

        XCTAssertEqual(fixture.store.notice?.title, "A selected account is already running")
        let attemptsAfterFriendJoin = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attemptsAfterFriendJoin, attemptsBeforeFriendJoin)
    }

    func testLoadRemovesSavedJobIDsButKeepsPrivateServerLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-temporary-server-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let jobID = "11111111-2222-3333-4444-555555555555"
        let privateLink = "https://www.roblox.com/games/1818?privateServerLinkCode=saved-choice"
        let accounts = [
            ManagedAccount(userID: 1, username: "temporary", displayName: "Temporary", savedServer: jobID),
            ManagedAccount(userID: 2, username: "private", displayName: "Private", savedServer: privateLink)
        ]
        try repository.save(accounts)

        let store = AccountStore(
            repository: repository,
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        XCTAssertEqual(store.accounts.first(where: { $0.id == accounts[0].id })?.savedServer, "")
        XCTAssertEqual(store.accounts.first(where: { $0.id == accounts[1].id })?.savedServer, privateLink)
        let saved = try repository.load()
        XCTAssertEqual(saved.first(where: { $0.id == accounts[0].id })?.savedServer, "")
        XCTAssertTrue(saved.first(where: { $0.id == accounts[1].id })?.savedServer.hasPrefix("keychain:private-server:") == true)
        XCTAssertFalse(saved.first(where: { $0.id == accounts[1].id })?.savedServer.contains("saved-choice") == true)
    }

    func testWebsitePlayLaunchesTheProfileAccountWithoutSavingThePageTarget() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let account = fixture.accounts[1]

        await fixture.store.launchFromWebsite(
            accountID: account.id,
            request: RobloxWebLaunchRequest(placeID: 1818, server: .automatic)
        )

        let attemptedAccountIDs = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attemptedAccountIDs, [account.id])
        XCTAssertTrue(fixture.store.runningAccountIDs.contains(account.id))
        let saved = try fixture.repository.load()
        let savedAccount = try XCTUnwrap(saved.first(where: { $0.id == account.id }))
        XCTAssertEqual(savedAccount.savedPlaceID, "")
        XCTAssertEqual(savedAccount.savedServer, "")
    }

    func testOpenRobloxAppUsesTheSelectedAccountWithoutAPlaceLaunch() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let account = fixture.accounts[1]

        await fixture.store.launchApp(account: account)

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        let urls = await fixture.launcher.attemptedURLs()
        XCTAssertEqual(attempts, [account.id])
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls[0].absoluteString.contains("launchmode:app"))
        XCTAssertFalse(urls[0].absoluteString.contains("placelauncherurl"))
        XCTAssertTrue(fixture.store.runningAccountIDs.contains(account.id))
    }

    func testSecondAppStartsWhileFirstAppIsStillOpening() async throws {
        let fixture = try makeFixture(launchDelayNanoseconds: 500_000_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let firstAccount = fixture.accounts[0]
        let secondAccount = fixture.accounts[1]

        let firstLaunch = Task { await fixture.store.launchApp(account: firstAccount) }
        for _ in 0..<100 {
            if await fixture.launcher.attemptedAccountIDs().contains(firstAccount.id) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let firstAttempts = await fixture.launcher.attemptedAccountIDs()
        XCTAssertTrue(firstAttempts.contains(firstAccount.id))

        let secondLaunch = Task { await fixture.store.launchApp(account: secondAccount) }
        for _ in 0..<100 {
            if await fixture.launcher.attemptedAccountIDs().contains(secondAccount.id) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let concurrentAttempts = await fixture.launcher.attemptedAccountIDs()
        XCTAssertEqual(concurrentAttempts, Set([firstAccount.id, secondAccount.id]))
        XCTAssertEqual(
            fixture.store.appOpeningAccountIDs,
            Set([firstAccount.id, secondAccount.id])
        )

        await firstLaunch.value
        await secondLaunch.value
        XCTAssertEqual(
            fixture.store.runningAccountIDs,
            Set([firstAccount.id, secondAccount.id])
        )
    }

    func testBulkOpenAppsStartsEverySelectedAccountWithoutJoiningAGame() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchSelectedApps()

        let urls = await fixture.launcher.attemptedURLs()
        let maximumConcurrentRequests = await fixture.api.maximumConcurrentTicketRequests()
        let attemptedAccountIDs = await fixture.launcher.attemptedAccountIDs()
        XCTAssertEqual(maximumConcurrentRequests, 3)
        XCTAssertEqual(attemptedAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls.allSatisfy { $0.absoluteString.contains("launchmode:app") })
        XCTAssertTrue(urls.allSatisfy { !$0.absoluteString.contains("placelauncherurl") })
        XCTAssertEqual(fixture.store.runningAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertTrue(fixture.store.batchSelectedIDs.isEmpty)
        XCTAssertEqual(fixture.store.batchStatus, "Opened all 3 apps")
        XCTAssertEqual(fixture.store.launchStatus, "Running 3 Roblox apps")
    }

    func testCurrentPrivateShareFromBuiltInBrowserResolvesForSelectedAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-web-private-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 1, username: "allowed", displayName: "Allowed")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("allow", for: account.id)
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: PrivateAccessMockAPI(),
            launcher: launcher
        )
        let deepLink = try XCTUnwrap(
            URL(string: "roblox://navigation/share_links?code=share-code&type=Server")
        )
        let request = try XCTUnwrap(RobloxWebLaunchRequestParser.parse(deepLink))

        await store.launchFromWebsite(accountID: account.id, request: request)

        let urls = await launcher.attemptedURLs()
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls[0].absoluteString.contains("placeId%3D17625359962"))
        XCTAssertTrue(urls[0].absoluteString.contains("RequestPrivateGame"))
        XCTAssertTrue(store.runningAccountIDs.contains(account.id))
    }

    func testConcurrentLaunchSetRequestsStartEachAccountOnlyOnce() async throws {
        let fixture = try makeFixture(launchDelayNanoseconds: 200_000_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let launchSet = LaunchSet(
            name: "Wave",
            accountIDs: fixture.accounts.map(\.id),
            placeID: 12345
        )

        async let firstRun: Void = fixture.store.runLaunchSet(launchSet)
        async let secondRun: Void = fixture.store.runLaunchSet(launchSet)
        _ = await (firstRun, secondRun)

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        XCTAssertEqual(attempts.count, fixture.accounts.count)
        XCTAssertEqual(Set(attempts), Set(fixture.accounts.map(\.id)))
        XCTAssertNil(fixture.store.runningLaunchSetID)
    }

    func testConcurrentBatchRequestsStartEachAccountOnlyOnce() async throws {
        let healthChecker = SlowReadyHealthChecker()
        let fixture = try makeFixture(healthChecker: healthChecker)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.toggleBatchGroup("Wave")

        async let firstRun: Void = fixture.store.launchBatch(placeText: "12345", server: .automatic)
        async let secondRun: Void = fixture.store.launchBatch(placeText: "12345", server: .automatic)
        _ = await (firstRun, secondRun)

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        let healthCheckCount = await healthChecker.checkCount()
        XCTAssertEqual(attempts.count, fixture.accounts.count)
        XCTAssertEqual(healthCheckCount, fixture.accounts.count)
    }

    func testConcurrentSingleRequestsStartTheAccountOnlyOnce() async throws {
        let healthChecker = SlowReadyHealthChecker()
        let fixture = try makeFixture(healthChecker: healthChecker)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let account = fixture.accounts[0]

        async let firstRun: Void = fixture.store.launch(
            account: account,
            placeText: "12345",
            server: .automatic
        )
        async let secondRun: Void = fixture.store.launch(
            account: account,
            placeText: "12345",
            server: .automatic
        )
        _ = await (firstRun, secondRun)

        let attempts = await fixture.launcher.orderedAttemptedAccountIDs()
        let healthCheckCount = await healthChecker.checkCount()
        XCTAssertEqual(attempts, [account.id])
        XCTAssertEqual(healthCheckCount, 1)
        XCTAssertNil(fixture.store.notice)
    }

    func testLaunchSetCarriesItsWindowPolicyIntoADeferredBatchLaunch() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let assignment = WindowLayoutAssignment(
            accountID: fixture.accounts[0].id,
            displayID: "saved-display",
            displayName: "Saved Display",
            displayPixelWidth: 2560,
            displayPixelHeight: 1440,
            region: .right
        )
        let launchSettings = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 7,
            overridesVolume: true,
            volume: 0.4
        )
        let launchSet = LaunchSet(
            name: "Choose Server",
            accountIDs: fixture.accounts.map(\.id),
            placeID: 12345,
            serverStrategy: .browseBeforeLaunch,
            launchSettings: launchSettings,
            windowArrangement: .custom([assignment])
        )

        await fixture.store.runLaunchSet(launchSet)

        XCTAssertEqual(fixture.store.batchSelectedIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(fixture.store.batchWindowArrangement, .custom([assignment]))
        XCTAssertEqual(fixture.store.batchLaunchSettingsOverride, launchSettings)
    }

    func testLaunchSetUsesItsSavedLaunchSettingsOverride() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let expected = RobloxLaunchSettings(
            graphics: .manual,
            graphicsQuality: 3,
            overridesVolume: true,
            volume: 0.25
        )
        let launchSet = LaunchSet(
            name: "Custom settings",
            accountIDs: fixture.accounts.map(\.id),
            placeID: 12345,
            launchSettings: expected
        )

        await fixture.store.runLaunchSet(launchSet)

        let attemptedSettings = await fixture.launcher.attemptedLaunchSettings()
        XCTAssertEqual(attemptedSettings, Array(repeating: expected, count: fixture.accounts.count))
        XCTAssertNil(fixture.store.batchLaunchSettingsOverride)
    }

    func testNormalClientExitClearsStaleRunningStatus() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let account = fixture.accounts[0]

        await fixture.store.launch(account: account, placeText: "1818", server: .automatic)
        XCTAssertTrue(fixture.store.launchStatus.hasPrefix("Running"))

        await fixture.launcher.simulateExit(accountID: account.id)
        await fixture.store.refreshRunningInstances()

        XCTAssertEqual(fixture.store.launchStatus, "Ready")
        XCTAssertEqual(fixture.store.batchStatus, "No managed Roblox clients are running")
        XCTAssertTrue(fixture.store.runningAccountIDs.isEmpty)
    }

    func testWebCookieRotationSavesOnlyTheSameRobloxUser() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-web-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "same", displayName: "Same")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: [
            "old": RobloxUser(id: 44, name: "same", displayName: "Same"),
            "rotated": RobloxUser(id: 44, name: "same", displayName: "Same")
        ])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: "rotated")

        XCTAssertEqual(try vault.read(for: account.id), "rotated")
        XCTAssertTrue(store.accountHealth[account.id]?.isReady == true)
    }

    func testWebCookieFromWrongAccountIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-wrong-web-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "expected", displayName: "Expected")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: ["wrong": RobloxUser(id: 99, name: "wrong", displayName: "Wrong")])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: "wrong")

        XCTAssertEqual(try vault.read(for: account.id), "old")
        XCTAssertEqual(store.accountHealth[account.id], .wrongAccount(actualUserID: 99))
    }

    func testWebLogoutChecksWhetherSavedSessionStillWorks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-web-logout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "same", displayName: "Same")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: ["old": RobloxUser(id: 44, name: "same", displayName: "Same")])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: nil)

        XCTAssertTrue(store.accountHealth[account.id]?.isReady == true)
        XCTAssertEqual(try vault.read(for: account.id), "old")
    }

    func testPrivateServerAccessDenialsAppearBeforeAnyLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-private-preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = [
            ManagedAccount(userID: 1, username: "allowed", displayName: "Allowed", group: "Wave"),
            ManagedAccount(userID: 2, username: "denied", displayName: "Denied", group: "Wave")
        ]
        try repository.save(accounts)
        let vault = MemoryVault()
        try vault.save("allow", for: accounts[0].id)
        try vault.save("deny", for: accounts[1].id)
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let api = PrivateAccessMockAPI()
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: launcher)
        store.toggleBatchGroup("Wave")

        await store.launchBatch(
            placeText: "1818",
            server: .privateLink("https://www.roblox.com/games/1818?privateServerLinkCode=private-code")
        )

        let attemptedAccountIDs = await launcher.attemptedAccountIDs()
        XCTAssertTrue(attemptedAccountIDs.isEmpty)
        XCTAssertEqual(store.batchSelectedIDs, [accounts[0].id])
        guard case .failed = store.batchStates[accounts[1].id] else {
            return XCTFail("Denied account must be shown before launch")
        }
    }

    func testCurrentShareLinkAccessDenialsAppearBeforeAnyLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-share-link-preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = [
            ManagedAccount(userID: 1, username: "allowed", displayName: "Allowed", group: "Wave"),
            ManagedAccount(userID: 2, username: "denied", displayName: "Denied", group: "Wave")
        ]
        try repository.save(accounts)
        let vault = MemoryVault()
        try vault.save("allow", for: accounts[0].id)
        try vault.save("deny", for: accounts[1].id)
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: PrivateAccessMockAPI(),
            launcher: launcher
        )
        store.toggleBatchGroup("Wave")

        await store.launchBatch(
            placeText: "17625359962",
            server: .privateLink("https://www.roblox.com/share?code=share-code&type=Server")
        )

        let attemptedAccountIDs = await launcher.attemptedAccountIDs()
        XCTAssertTrue(attemptedAccountIDs.isEmpty)
        XCTAssertEqual(store.batchSelectedIDs, [accounts[0].id])
        guard case .failed = store.batchStates[accounts[1].id] else {
            return XCTFail("Denied account must be shown before launch")
        }
    }

    func testCurrentShareLinkCanBeSavedThroughASignedInAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-share-link-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 1, username: "allowed", displayName: "Allowed")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("allow", for: account.id)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: PrivateAccessMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )
        let link = "https://www.roblox.com/share?code=share-code&type=Server"

        let savedResult = await store.savePrivateServer(name: "Friends", link: link)
        let saved = try XCTUnwrap(savedResult)

        XCTAssertEqual(saved.placeID, 17_625_359_962)
        XCTAssertEqual(saved.link, link)
        XCTAssertEqual(store.privateServers, [saved])
    }

    func testPrivateServerLibrarySavesUpdatesReloadsAndRemovesLinks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-private-library-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let link = "https://www.roblox.com/games/1818/Example?privateServerLinkCode=secret-code"
        let vault = MemoryVault()
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        let firstResult = await store.savePrivateServer(name: "Friends", link: link)
        let updatedResult = await store.savePrivateServer(name: "Weekend group", link: link)
        let first = try XCTUnwrap(firstResult)
        let updated = try XCTUnwrap(updatedResult)

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(store.privateServers.count, 1)
        XCTAssertEqual(store.privateServers.first?.name, "Weekend group")
        XCTAssertEqual(store.privateServers.first?.placeID, 1818)
        let exported = try store.exportMetadata()
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("secret-code"))

        let reloaded = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )
        XCTAssertEqual(reloaded.privateServers, store.privateServers)

        reloaded.removePrivateServer(updated)
        XCTAssertTrue(reloaded.privateServers.isEmpty)
        XCTAssertTrue(try PrivateServerRepository(
            fileName: "PrivateServers.json",
            dataDirectory: directory
        ).load().isEmpty)
    }

    func testExistingAccountPrivateLinkMigratesIntoLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-private-migration-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let link = "https://www.roblox.com/games/999/Example?privateServerLinkCode=old-code"
        try repository.save([
            ManagedAccount(
                userID: 99,
                username: "builder",
                displayName: "Builder",
                savedPlaceID: "999",
                savedServer: link
            )
        ])

        let vault = MemoryVault()
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        XCTAssertEqual(store.privateServers.count, 1)
        XCTAssertEqual(store.privateServers.first?.placeID, 999)
        XCTAssertEqual(store.privateServers.first?.link, link)
        let saved = try PrivateServerRepository(
            fileName: "PrivateServers.json",
            dataDirectory: directory
        ).load()
        XCTAssertTrue(saved.first?.link.hasPrefix("keychain:private-server:") == true)
        XCTAssertFalse(saved.first?.link.contains("old-code") == true)
        for name in ["Accounts.json", "Accounts.backup.json", "PrivateServers.json", "PrivateServers.backup.json"] {
            let text = String(decoding: try Data(contentsOf: directory.appendingPathComponent(name)), as: UTF8.self)
            XCTAssertFalse(text.contains("old-code"))
        }
    }

    func testLegacyPlainTextProfileNoteMovesToKeychainAndIsScrubbedFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-note-migration-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let account = ManagedAccount(userID: 71, username: "notes", displayName: "Notes")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([account])) as? [[String: Any]]
        )
        object[0]["notes"] = "legacy private note"
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        try legacyData.write(to: directory.appendingPathComponent("Accounts.json"))
        try legacyData.write(to: directory.appendingPathComponent("Accounts.backup.json"))
        let repository = AccountRepository(dataDirectory: directory)
        let vault = MemoryVault()

        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )

        XCTAssertEqual(store.accounts.first?.notes, "legacy private note")
        XCTAssertEqual(try vault.readNote(for: account.id), "legacy private note")
        for name in ["Accounts.json", "Accounts.backup.json"] {
            let text = String(decoding: try Data(
                contentsOf: directory.appendingPathComponent(name)
            ), as: UTF8.self)
            XCTAssertFalse(text.contains("legacy private note"))
        }

        var updated = try XCTUnwrap(store.accounts.first)
        updated.notes = "new encrypted note"
        store.update(updated)
        let reloaded = AccountStore(
            repository: repository,
            vault: vault,
            api: BatchMockAPI(),
            launcher: BatchMockLauncher(failingAccountID: nil)
        )
        XCTAssertEqual(reloaded.accounts.first?.notes, "new encrypted note")
    }

    private func makeFixture(
        failingIndex: Int? = nil,
        launchDelayNanoseconds: UInt64 = 0,
        healthChecker: (any AccountHealthChecking)? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-batch-tests-\(UUID().uuidString)", isDirectory: true)
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<3).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "account_\(index + 1)",
                displayName: "Account \(index + 1)",
                group: "Wave"
            )
        }
        try repository.save(accounts)

        let vault = MemoryVault()
        for account in accounts {
            try vault.save("cookie-\(account.userID)", for: account.id)
        }
        let api = BatchMockAPI()
        let failingID = failingIndex.map { accounts[$0].id }
        let launcher = BatchMockLauncher(
            failingAccountID: failingID,
            launchDelayNanoseconds: launchDelayNanoseconds
        )
        let friendRelay = BatchMockFriendRelay()
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: api,
            launcher: launcher,
            launchMode: .unmodifiedParallel,
            friendRelay: friendRelay,
            healthChecker: healthChecker
        )
        return Fixture(
            directory: directory,
            repository: repository,
            accounts: accounts,
            api: api,
            launcher: launcher,
            friendRelay: friendRelay,
            store: store
        )
    }
}

private actor SlowReadyHealthChecker: AccountHealthChecking {
    private var checks = 0

    func check(_ account: ManagedAccount) async -> AccountHealth {
        checks += 1
        try? await Task.sleep(nanoseconds: 100_000_000)
        return .ready(lastChecked: Date())
    }

    func checkCount() -> Int { checks }
}

private actor CountingHealthChecker: AccountHealthChecking {
    private var checkedIDs: [UUID] = []

    func check(_ account: ManagedAccount) async -> AccountHealth {
        checkedIDs.append(account.id)
        return .ready(lastChecked: Date())
    }

    func checkedAccountIDs() -> Set<UUID> {
        Set(checkedIDs)
    }

    func checkCount() -> Int {
        checkedIDs.count
    }
}

private actor WebSessionMockAPI: RobloxAPIProviding {
    let usersByCookie: [String: RobloxUser]
    init(usersByCookie: [String: RobloxUser]) { self.usersByCookie = usersByCookie }
    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        guard let user = usersByCookie[RobloxAPIClient.normalizedCookie(from: rawCookie)] else {
            throw RobloxAPIError.invalidSession
        }
        return user
    }
    func avatarURL(userID: Int64) async -> URL? { nil }
    func authenticationTicket(cookie rawCookie: String) async throws -> String { "ticket" }
    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String { "access" }
}

private struct ExperienceMetadataMock: ExperienceMetadataProviding {
    func metadata(placeID: Int64) async throws -> ExperienceMetadata {
        ExperienceMetadata(
            placeID: placeID,
            universeID: 13058,
            name: "Classic: Crossroads",
            thumbnailURLString: "https://tr.rbxcdn.com/crossroads.png"
        )
    }
}

private actor PrivateAccessMockAPI: RobloxAPIProviding {
    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        if rawCookie == "allow" { return RobloxUser(id: 1, name: "allowed", displayName: "Allowed") }
        if rawCookie == "deny" { return RobloxUser(id: 2, name: "denied", displayName: "Denied") }
        throw RobloxAPIError.invalidSession
    }
    func avatarURL(userID: Int64) async -> URL? { nil }
    func authenticationTicket(cookie rawCookie: String) async throws -> String { "ticket" }
    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String {
        if rawCookie == "deny" { throw RobloxAPIError.privateServerUnavailable }
        return "access"
    }
    func privateShareLinkResolution(
        shareCode: String,
        cookie rawCookie: String
    ) async throws -> RobloxPrivateShareLinkResolution {
        if rawCookie == "deny" { throw RobloxAPIError.privateServerUnavailable }
        return RobloxPrivateShareLinkResolution(
            placeID: 17_625_359_962,
            linkCode: "resolved-private-code"
        )
    }
}

private struct Fixture {
    let directory: URL
    let repository: AccountRepository
    let accounts: [ManagedAccount]
    let api: BatchMockAPI
    let launcher: BatchMockLauncher
    let friendRelay: BatchMockFriendRelay
    let store: AccountStore
}

private actor BatchMockFriendRelay: FriendRelayProviding {
    private var configuredPlan: FriendRelayPlan?
    private var arrivals: [UUID: FriendRelayArrival] = [:]
    private var waitNanoseconds: UInt64 = 0

    func setPlan(_ plan: FriendRelayPlan) {
        configuredPlan = plan
    }

    func setArrival(_ arrival: FriendRelayArrival, for accountID: UUID) {
        arrivals[accountID] = arrival
    }

    func setWaitNanoseconds(_ value: UInt64) {
        waitNanoseconds = value
    }

    func plan(accounts: [ManagedAccount], sourceAccountIDs: Set<UUID>) -> FriendRelayPlan {
        if let configuredPlan { return configuredPlan }
        let selectedIDs = Set(accounts.map(\.id))
        let roots = sourceAccountIDs.intersection(selectedIDs)
        var friends: [UUID: Set<UUID>] = [:]
        var levels: [UUID: Int] = [:]
        for account in accounts {
            if roots.contains(account.id) {
                friends[account.id] = selectedIDs.subtracting([account.id])
                levels[account.id] = 0
            } else {
                friends[account.id] = roots
                levels[account.id] = 1
            }
        }
        return FriendRelayPlan(
            sourceAccountIDs: roots,
            friendAccountIDs: friends,
            levels: levels
        )
    }

    func waitForServer(
        account: ManagedAccount,
        session: String,
        placeID: Int64,
        jobID: String
    ) async -> FriendRelayArrival {
        if waitNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: waitNanoseconds)
        }
        return arrivals[account.id] ?? .arrived
    }
}

private final class MemoryVault: SecretVault, ProfileNoteVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    private var notes: [UUID: String] = [:]
    private var capabilities: [String: String] = [:]

    func save(_ secret: String, for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        values[accountID] = secret
    }

    func read(for accountID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[accountID]
    }

    func delete(for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        values[accountID] = nil
    }

    func savePrivateServerCapabilities(_ capabilities: [String: String]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.capabilities = capabilities
    }

    func readPrivateServerCapabilities() throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return capabilities
    }

    func saveNote(_ note: String, for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        notes[accountID] = note
    }

    func readNote(for accountID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return notes[accountID]
    }

    func deleteNote(for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        notes[accountID] = nil
    }
}

private actor BatchMockAPI: RobloxAPIProviding {
    private var activeTicketRequests = 0
    private var maximumActiveTicketRequests = 0
    private var publicServerRequests = 0

    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        guard let userID = Int64(rawCookie.replacingOccurrences(of: "cookie-", with: "")) else {
            throw RobloxAPIError.invalidSession
        }
        return RobloxUser(id: userID, name: "account_\(userID)", displayName: "Account \(userID)")
    }

    func avatarURL(userID: Int64) async -> URL? { nil }

    func authenticationTicket(cookie rawCookie: String) async throws -> String {
        activeTicketRequests += 1
        maximumActiveTicketRequests = max(maximumActiveTicketRequests, activeTicketRequests)
        try await Task.sleep(nanoseconds: 100_000_000)
        activeTicketRequests -= 1
        return "ticket-\(rawCookie)"
    }

    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String {
        "access-\(rawCookie)"
    }

    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage {
        publicServerRequests += 1
        return RobloxPublicServerPage(data: [
            RobloxPublicServer(
                id: "11111111-2222-3333-4444-555555555555",
                maxPlayers: 8,
                playing: 2,
                ping: 80
            )
        ])
    }

    func user(named username: String) async throws -> RobloxUserSearchResult {
        RobloxUserSearchResult(id: 156, name: "builderman", displayName: "builderman")
    }

    func presence(userID: Int64) async throws -> RobloxUserPresence {
        RobloxUserPresence(
            userPresenceType: 2,
            lastLocation: "Test Place",
            placeId: 1818,
            rootPlaceId: 1818,
            gameId: "11111111-2222-3333-4444-555555555555",
            universeId: 13058,
            userId: userID
        )
    }

    func maximumConcurrentTicketRequests() -> Int {
        maximumActiveTicketRequests
    }

    func publicServerRequestCount() -> Int {
        publicServerRequests
    }
}

private actor BatchMockLauncher: ParallelRobloxLaunching {
    private let failingAccountID: UUID?
    private let launchDelayNanoseconds: UInt64
    private let launchDelaysByAccountID: [UUID: UInt64]
    private let blockedAccountIDs: Set<UUID>
    private var pendingBlockedLaunches: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var releasedBlockedAccountIDs = Set<UUID>()
    private var attempted = Set<UUID>()
    private var orderedAttempts: [UUID] = []
    private var modes = Set<RobloxLaunchMode>()
    private var launchSettings: [RobloxLaunchSettings] = []
    private var running = Set<UUID>()
    private var urls: [URL] = []
    private var batchStopRequests: [[UUID]] = []
    private var processIdentifiers: [UUID: Int32] = [:]

    init(
        failingAccountID: UUID?,
        launchDelayNanoseconds: UInt64 = 0,
        launchDelaysByAccountID: [UUID: UInt64] = [:],
        blockedAccountIDs: Set<UUID> = []
    ) {
        self.failingAccountID = failingAccountID
        self.launchDelayNanoseconds = launchDelayNanoseconds
        self.launchDelaysByAccountID = launchDelaysByAccountID
        self.blockedAccountIDs = blockedAccountIDs
    }

    func launch(
        _ url: URL,
        for accountID: UUID,
        mode: RobloxLaunchMode,
        settings: RobloxLaunchSettings
    ) async throws -> ParallelRobloxInstance {
        attempted.insert(accountID)
        orderedAttempts.append(accountID)
        modes.insert(mode)
        launchSettings.append(settings)
        urls.append(url)
        if accountID == failingAccountID { throw RobloxLaunchError.openFailed }
        if blockedAccountIDs.contains(accountID), releasedBlockedAccountIDs.remove(accountID) == nil {
            await withCheckedContinuation { pendingBlockedLaunches[accountID] = $0 }
        }
        let delay = launchDelaysByAccountID[accountID] ?? launchDelayNanoseconds
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        running.insert(accountID)
        let processIdentifier = Int32(processIdentifiers.count + 1)
        processIdentifiers[accountID] = processIdentifier
        return ParallelRobloxInstance(
            accountID: accountID,
            processIdentifier: processIdentifier,
            applicationURL: URL(fileURLWithPath: "/tmp/Roblox.app")
        )
    }

    func runningAccountIDs(from accountIDs: [UUID]) async -> Set<UUID> {
        running.intersection(accountIDs)
    }

    func stop(accountID: UUID) async -> Bool {
        running.remove(accountID)
        return true
    }

    func stop(accountIDs: [UUID]) async -> Set<UUID> {
        batchStopRequests.append(accountIDs)
        let stopped = running.intersection(accountIDs)
        running.subtract(stopped)
        return stopped
    }

    func removeStaleCopies() async {}

    func removePreparedCopy(accountID: UUID) async {}

    func attemptedAccountIDs() -> Set<UUID> {
        attempted
    }

    func orderedAttemptedAccountIDs() -> [UUID] { orderedAttempts }

    func simulateExit(accountID: UUID) {
        running.remove(accountID)
    }

    func attemptedModes() -> Set<RobloxLaunchMode> {
        modes
    }

    func attemptedLaunchSettings() -> [RobloxLaunchSettings] { launchSettings }

    func attemptedURLs() -> [URL] { urls }

    func batchStopRequestCount() -> Int { batchStopRequests.count }

    func processIdentifiersByAccount() -> [UUID: Int32] { processIdentifiers }

    func releaseBlockedLaunch(for accountID: UUID) {
        if let continuation = pendingBlockedLaunches.removeValue(forKey: accountID) {
            continuation.resume()
        } else {
            releasedBlockedAccountIDs.insert(accountID)
        }
    }
}

private var batchTestDisplay: ConnectedDisplay {
    ConnectedDisplay(
        id: "batch-display",
        name: "Batch Display",
        frame: CGRect(x: 0, y: 0, width: 1400, height: 1000),
        visibleFrame: CGRect(x: 100, y: 50, width: 1200, height: 800),
        pixelWidth: 2800,
        pixelHeight: 2000,
        usablePixelWidth: 2400,
        usablePixelHeight: 1600
    )
}

private final class BatchMemoryWindowLayoutRepository: WindowLayoutPersisting {
    private var assignments: [WindowLayoutAssignment] = []
    func load() -> [WindowLayoutAssignment] { assignments }
    func save(_ assignments: [WindowLayoutAssignment]) { self.assignments = assignments }
}

private struct BatchStaticDisplayProvider: ConnectedDisplayProviding {
    let snapshotValue: ConnectedDisplaySnapshot
    @MainActor func snapshot() -> ConnectedDisplaySnapshot { snapshotValue }
}

@MainActor
private final class BatchAccessibilityPermissionManager: AccessibilityPermissionManaging {
    private let trusted: Bool

    init(trusted: Bool = true) {
        self.trusted = trusted
    }

    func isTrusted() -> Bool { trusted }
    func requestAccess() {}
}

private actor BatchRecordingWindowPlacer: RobloxWindowPlacing {
    struct Request: Equatable {
        let processIdentifier: Int32
        let request: RobloxWindowPlacementRequest
    }
    private var requests: [Request] = []
    private let result: WindowPlacementResult
    private let onPlace: @Sendable () -> Void

    init(
        result: WindowPlacementResult = .placed,
        onPlace: @escaping @Sendable () -> Void = {}
    ) {
        self.result = result
        self.onPlace = onPlace
    }

    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult {
        requests.append(Request(processIdentifier: processIdentifier, request: request))
        if requests.count == 1 { onPlace() }
        return result
    }

    func recordedRequests() -> [Request] { requests }
}

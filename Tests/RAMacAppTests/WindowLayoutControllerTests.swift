import AppKit
import ApplicationServices
import CoreGraphics
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class WindowLayoutControllerTests: XCTestCase {
    func testFullScreenWindowOnlyMatchesItsOwnDisplay() {
        let left = CGRect(x: -1600, y: 40, width: 1600, height: 1000)
        let right = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowPlacementGeometry.isOnDisplay(left, display: left))
        XCTAssertFalse(WindowPlacementGeometry.isOnDisplay(left, display: right))
        XCTAssertFalse(WindowPlacementGeometry.isOnDisplay(.zero, display: right))
    }

    func testRegionsUseHalvesQuartersAndWholeVisibleFrame() {
        let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)

        XCTAssertEqual(
            WindowPlacementGeometry.frame(in: visible, region: .topLeft),
            CGRect(x: 100, y: 450, width: 600, height: 400)
        )
        XCTAssertEqual(
            WindowPlacementGeometry.frame(in: visible, region: .right),
            CGRect(x: 700, y: 50, width: 600, height: 800)
        )
        XCTAssertEqual(
            WindowPlacementGeometry.frame(in: visible, region: .bottom),
            CGRect(x: 100, y: 50, width: 1200, height: 400)
        )
        XCTAssertEqual(
            WindowPlacementGeometry.frame(in: visible, region: .wholeScreen),
            visible
        )
    }

    func testAccessibilityCoordinatesUseTopLeftScreenOrigin() {
        let appKitFrame = CGRect(x: 100, y: 450, width: 600, height: 400)

        XCTAssertEqual(
            WindowPlacementGeometry.accessibilityFrame(from: appKitFrame, referenceTop: 1000),
            CGRect(x: 100, y: 150, width: 600, height: 400)
        )
    }

    func testConstrainedWindowAnchorsToBottomRightOfUsableDisplay() {
        let available = CGRect(x: 100, y: 40, width: 1400, height: 900)

        XCTAssertEqual(
            WindowPlacementGeometry.anchoredAccessibilityFrame(
                size: CGSize(width: 800, height: 628),
                in: available,
                region: .bottomRight
            ),
            CGRect(x: 700, y: 312, width: 800, height: 628)
        )
    }

    func testConstrainedWindowCentersOnTopEdge() {
        let available = CGRect(x: 100, y: 40, width: 1400, height: 900)

        XCTAssertEqual(
            WindowPlacementGeometry.anchoredAccessibilityFrame(
                size: CGSize(width: 800, height: 628),
                in: available,
                region: .top
            ),
            CGRect(x: 400, y: 40, width: 800, height: 628)
        )
    }

    func testWindowLargerThanUsableDisplayStaysAtDisplayOrigin() {
        let available = CGRect(x: 100, y: 40, width: 700, height: 500)

        XCTAssertEqual(
            WindowPlacementGeometry.anchoredAccessibilityFrame(
                size: CGSize(width: 800, height: 628),
                in: available,
                region: .bottomRight
            ).origin,
            available.origin
        )
    }

    func testAdjustedPlacementReportsTheWindowSizeLimit() {
        let result = WindowPlacementResult.adjusted("Roblox kept this window at 800 × 628.")

        XCTAssertEqual(result.message, "Roblox kept this window at 800 × 628.")
        XCTAssertEqual(result.requiresAttentionMessage, result.message)
    }

    func testOverlapDetectionMatchesSnapRegions() {
        XCTAssertTrue(WindowPlacementGeometry.regionsOverlap(.left, .topLeft))
        XCTAssertTrue(WindowPlacementGeometry.regionsOverlap(.wholeScreen, .bottomRight))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.left, .right))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.top, .bottom))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.topLeft, .bottomLeft))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.fullScreen, .wholeScreen))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.fullScreen, .fullScreen))
    }

    func testAutomaticLayoutUsesAppleStyleThreeWindowArrangement() {
        let fixture = makeControllerFixture()
        let accountIDs = [UUID(), UUID(), UUID()]

        let assignments = WindowArrangementPlanner.automaticAssignments(
            accountIDs: accountIDs,
            displays: [fixture.display]
        )

        XCTAssertEqual(assignments?.map(\.accountID), accountIDs)
        XCTAssertEqual(assignments?.map(\.region), [.left, .topRight, .bottomRight])
    }

    func testAutomaticLayoutRefusesMoreThanFourProfilesPerDisplay() {
        let fixture = makeControllerFixture()

        XCTAssertNil(
            WindowArrangementPlanner.automaticAssignments(
                accountIDs: (0..<5).map { _ in UUID() },
                displays: [fixture.display]
            )
        )
    }

    func testSeveralProfilesCanUseSeparateFullScreenSpacesOnOneDisplay() {
        let fixture = makeControllerFixture()
        let accountIDs = [UUID(), UUID(), UUID()]

        for accountID in accountIDs {
            fixture.controller.assign(accountID: accountID, to: fixture.display, region: .fullScreen)
        }

        XCTAssertEqual(fixture.controller.assignments.count, 3)
        XCTAssertTrue(fixture.controller.assignments.values.allSatisfy { $0.region == .fullScreen })
    }

    func testLiveFullScreenPlacementSurvivesAppAndSpaceSwitchingWhenEnabled() async throws {
        guard let rawProcessIdentifier = ProcessInfo.processInfo.environment[
            "RAM_RUN_WINDOW_FULLSCREEN_INTEGRATION_PID"
        ], let processIdentifier = Int32(rawProcessIdentifier) else {
            throw XCTSkip("Set RAM_RUN_WINDOW_FULLSCREEN_INTEGRATION_PID to a windowed Roblox process ID.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("The test runner needs macOS Accessibility permission.")
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var mainWindowValue: CFTypeRef?
        let hasMainWindow = AXUIElementCopyAttributeValue(
            application,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        ) == .success
            && mainWindowValue.map { CFGetTypeID($0) == AXUIElementGetTypeID() } == true
        var windowsValue: CFTypeRef?
        let windowsReadSucceeded = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success
        let hasWindowListWindow = windowsReadSucceeded
            && (windowsValue as? [AXUIElement])?.isEmpty == false
        guard hasMainWindow || hasWindowListWindow else {
            throw XCTSkip("The selected Roblox process must have a visible window before the test starts.")
        }

        let snapshot = SystemConnectedDisplayProvider().snapshot()
        let display = try XCTUnwrap(snapshot.displays.first)
        let targetFrame = WindowPlacementGeometry.accessibilityFrame(
            from: display.visibleFrame,
            referenceTop: snapshot.accessibilityReferenceTop
        )
        let request = RobloxWindowPlacementRequest(
            targetFrame: targetFrame,
            availableFrame: targetFrame,
            screenFrame: WindowPlacementGeometry.accessibilityFrame(
                from: display.frame,
                referenceTop: snapshot.accessibilityReferenceTop
            ),
            region: .fullScreen
        )

        let interferenceProcess = ProcessInfo.processInfo.environment[
            "RAM_WINDOW_FULLSCREEN_INTERFERENCE_PID"
        ].flatMap(Int32.init).flatMap(NSRunningApplication.init(processIdentifier:))
        let appSwitching = Task { @MainActor in
            for _ in 0..<25 {
                if let finder = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.finder"
                ).first {
                    _ = finder.activate()
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                if let interferenceProcess {
                    _ = interferenceProcess.activate(options: [.activateAllWindows])
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        let result = await AccessibilityRobloxWindowPlacer().place(
            processIdentifier: processIdentifier,
            request: request
        )
        await appSwitching.value

        XCTAssertEqual(result, .placed)
    }

    func testLargerRegionClearsProfilesInOverlappingRegions() {
        let fixture = makeControllerFixture()
        let first = UUID()
        let second = UUID()
        let third = UUID()

        fixture.controller.assign(accountID: first, to: fixture.display, region: .topLeft)
        fixture.controller.assign(accountID: second, to: fixture.display, region: .bottomLeft)
        fixture.controller.assign(accountID: third, to: fixture.display, region: .left)

        XCTAssertNil(fixture.controller.assignment(for: first))
        XCTAssertNil(fixture.controller.assignment(for: second))
        XCTAssertEqual(fixture.controller.assignment(for: third)?.region, .left)
        XCTAssertEqual(fixture.controller.assignments.count, 1)
    }

    func testAssignmentsPersistAndReload() {
        let repository = MemoryWindowLayoutRepository()
        let fixture = makeControllerFixture(repository: repository)
        let accountID = UUID()
        fixture.controller.assign(accountID: accountID, to: fixture.display, region: .bottomRight)

        let reloaded = WindowLayoutController(
            repository: repository,
            displayProvider: StaticDisplayProvider(snapshotValue: fixture.snapshot),
            placer: RecordingWindowPlacer()
        )

        XCTAssertEqual(reloaded.assignment(for: accountID)?.region, .bottomRight)
        XCTAssertEqual(reloaded.assignment(for: accountID)?.displayName, "Test Display")
    }

    func testMissingAccountAssignmentsAreRemoved() {
        let fixture = makeControllerFixture()
        let keptAccountID = UUID()
        let removedAccountID = UUID()
        fixture.controller.assign(accountID: keptAccountID, to: fixture.display, region: .topLeft)
        fixture.controller.assign(accountID: removedAccountID, to: fixture.display, region: .bottomRight)

        fixture.controller.removeAssignmentsForMissingAccounts(validAccountIDs: [keptAccountID])

        XCTAssertNotNil(fixture.controller.assignment(for: keptAccountID))
        XCTAssertNil(fixture.controller.assignment(for: removedAccountID))
    }

    func testPlacementUsesCurrentVisibleFrameAndExactProcessID() async {
        let placer = RecordingWindowPlacer()
        let fixture = makeControllerFixture(placer: placer)
        let accountID = UUID()
        fixture.controller.assign(accountID: accountID, to: fixture.display, region: .topRight)

        let result = await fixture.controller.placeWindow(accountID: accountID, processIdentifier: 4321)
        let requests = await placer.recordedRequests()

        XCTAssertEqual(result, .placed)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.processIdentifier, 4321)
        XCTAssertEqual(
            requests.first?.request.targetFrame,
            CGRect(x: 700, y: 150, width: 600, height: 400)
        )
        XCTAssertEqual(
            requests.first?.request.availableFrame,
            CGRect(x: 100, y: 150, width: 1200, height: 800)
        )
        XCTAssertEqual(
            requests.first?.request.screenFrame,
            CGRect(x: 0, y: 0, width: 1400, height: 1000)
        )
        XCTAssertEqual(requests.first?.request.region, .topRight)
    }

    func testMissingDisplayDoesNotMoveWindowToAnotherMonitor() async {
        let repository = MemoryWindowLayoutRepository()
        let placer = RecordingWindowPlacer()
        let original = makeControllerFixture(repository: repository, placer: placer)
        let accountID = UUID()
        original.controller.assign(accountID: accountID, to: original.display, region: .left)
        let disconnected = WindowLayoutController(
            repository: repository,
            displayProvider: StaticDisplayProvider(
                snapshotValue: ConnectedDisplaySnapshot(displays: [], accessibilityReferenceTop: 1000)
            ),
            placer: placer
        )

        let result = await disconnected.placeWindow(accountID: accountID, processIdentifier: 99)
        let requests = await placer.recordedRequests()

        XCTAssertEqual(result, .displayUnavailable("Test Display"))
        XCTAssertTrue(requests.isEmpty)
    }

    func testExplicitAssignmentsOverrideSavedPlacementsWithoutPersisting() async {
        let placer = RecordingWindowPlacer()
        let fixture = makeControllerFixture(placer: placer)
        let accountID = UUID()
        fixture.controller.assign(accountID: accountID, to: fixture.display, region: .left)
        let custom = WindowLayoutAssignment(
            accountID: accountID,
            displayID: fixture.display.id,
            displayName: fixture.display.name,
            displayPixelWidth: fixture.display.pixelWidth,
            displayPixelHeight: fixture.display.pixelHeight,
            region: .bottomRight
        )

        let results = await fixture.controller.placeWindows(
            [(accountID, 4101)],
            with: [custom]
        )
        let requests = await placer.recordedRequests()

        XCTAssertEqual(results[accountID], .placed)
        XCTAssertEqual(requests.first?.request.region, .bottomRight)
        XCTAssertEqual(fixture.controller.assignment(for: accountID)?.region, .left)
    }

    func testPermissionRequestRegistersCurrentAppAndRefreshesStatus() {
        let permissionManager = TestAccessibilityPermissionManager(isTrusted: false)
        let fixture = makeControllerFixture(permissionManager: permissionManager)

        XCTAssertFalse(fixture.controller.accessibilityPermissionGranted)
        fixture.controller.requestAccessibilityPermission()

        XCTAssertEqual(permissionManager.requestCount, 1)
        XCTAssertTrue(fixture.controller.accessibilityPermissionGranted)
    }

    func testPermissionCanBeCheckedAgainAfterSystemSettingsChanges() {
        let permissionManager = TestAccessibilityPermissionManager(isTrusted: false)
        let fixture = makeControllerFixture(permissionManager: permissionManager)
        permissionManager.trusted = true

        fixture.controller.refreshAccessibilityPermission()

        XCTAssertTrue(fixture.controller.accessibilityPermissionGranted)
    }

    func testPermissionGateStopsArrangementUntilAccessIsGranted() {
        let permissionManager = TestAccessibilityPermissionManager(
            isTrusted: false,
            trustsAfterRequest: false
        )
        let fixture = makeControllerFixture(permissionManager: permissionManager)

        XCTAssertFalse(fixture.controller.ensureAccessibilityPermission())
        XCTAssertEqual(permissionManager.requestCount, 1)
        XCTAssertFalse(fixture.controller.accessibilityPermissionGranted)
        XCTAssertEqual(
            fixture.controller.lastMessage,
            "Allow Window Control in System Settings before arranging Roblox windows."
        )
    }

    func testCapturedWindowReappliesItsPositionWithinTheDisplay() async throws {
        let frame = CGRect(x: 340, y: 310, width: 600, height: 400)
        let placer = RecordingWindowPlacer(snapshot: RobloxWindowSnapshot(frame: frame, isFullScreen: false))
        let fixture = makeControllerFixture(placer: placer)
        let accountID = UUID()
        let launches = [(accountID: accountID, processIdentifier: Int32(4321))]
        let assignments = await fixture.controller.captureWindows(launches)
        let assignment = try XCTUnwrap(assignments.first)
        XCTAssertEqual(assignment.relativeFrame, CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))

        let result = await fixture.controller.placeWindows(launches, with: assignments)
        let requests = await placer.recordedRequests()
        XCTAssertEqual(result[accountID], .placed)
        XCTAssertEqual(requests.first?.request.targetFrame, frame)
        XCTAssertEqual(requests.first?.request.usesCapturedFrame, true)
    }

    func testInvalidSavedWindowPositionDoesNotReachAccessibility() async {
        let placer = RecordingWindowPlacer()
        let fixture = makeControllerFixture(placer: placer)
        let accountID = UUID()
        let display = fixture.display
        let invalid = WindowLayoutAssignment(
            accountID: accountID, displayID: display.id, displayName: display.name,
            displayPixelWidth: display.pixelWidth, displayPixelHeight: display.pixelHeight,
            region: .wholeScreen, relativeFrame: CGRect(x: 0.8, y: 0, width: 0.8, height: 0.5)
        )

        let results = await fixture.controller.placeWindows(
            [(accountID: accountID, processIdentifier: 4321)], with: [invalid]
        )
        let requests = await placer.recordedRequests()
        XCTAssertEqual(results[accountID], .failed("This saved window position is invalid."))
        XCTAssertTrue(requests.isEmpty)
    }

    func testLiveWindowLayoutCaptureAndRestoreWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RAM_RUN_LIVE_WINDOW_LAYOUT"] == "1" else {
            throw XCTSkip("Enable RAM_RUN_LIVE_WINDOW_LAYOUT for the isolated Roblox window test.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("The test runner needs macOS Accessibility permission.")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-layout-integration-\(UUID().uuidString)", isDirectory: true)
        let launcher = ParallelRobloxLauncher(instancesRoot: root)
        let accountID = UUID()
        addTeardownBlock {
            _ = await launcher.stop(accountID: accountID)
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }

        let url = try RobloxLaunchURLBuilder().makeAppURL(ticket: "invalid-layout-integration-ticket")
        let instance = try await launcher.launch(url, for: accountID, mode: .unmodifiedParallel)
        let launches = [(accountID: accountID, processIdentifier: instance.processIdentifier)]

        let controller = WindowLayoutController(repository: MemoryWindowLayoutRepository())
        var original: [WindowLayoutAssignment] = []
        for _ in 0..<20 {
            original = await controller.captureWindows(launches)
            if !original.isEmpty { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        if let fullScreen = original.first, fullScreen.region == .fullScreen {
            let windowed = WindowLayoutAssignment(
                accountID: accountID, displayID: fullScreen.displayID, displayName: fullScreen.displayName,
                displayPixelWidth: fullScreen.displayPixelWidth, displayPixelHeight: fullScreen.displayPixelHeight,
                region: .wholeScreen, relativeFrame: CGRect(x: 0.12, y: 0.1, width: 0.75, height: 0.75)
            )
            let results = await controller.placeWindows(launches, with: [windowed])
            XCTAssertEqual(results[accountID], .placed)
            original = await controller.captureWindows(launches)
        }
        let window = try XCTUnwrap(original.first)
        let expected = try XCTUnwrap(window.relativeFrame)
        let destination = WindowLayoutAssignment(
            accountID: accountID, displayID: window.displayID, displayName: window.displayName,
            displayPixelWidth: window.displayPixelWidth, displayPixelHeight: window.displayPixelHeight,
            region: expected.midX < 0.5 ? .right : .left
        )
        let fullScreen = WindowLayoutAssignment(
            accountID: accountID, displayID: window.displayID, displayName: window.displayName,
            displayPixelWidth: window.displayPixelWidth, displayPixelHeight: window.displayPixelHeight,
            region: .fullScreen
        )
        let enteredFullScreen = await controller.placeWindows(launches, with: [fullScreen])
        XCTAssertEqual(enteredFullScreen[accountID], .placed)
        let fullScreenCapture = await controller.captureWindows(launches)
        XCTAssertEqual(fullScreenCapture.first?.region, .fullScreen)

        let moved = await controller.placeWindows(launches, with: [destination])
        let moveResult = try XCTUnwrap(moved[accountID])
        if case .adjusted = moveResult {} else { XCTAssertEqual(moveResult, .placed) }
        let rearranged = await controller.captureWindows(launches)
        XCTAssertEqual(rearranged.count, 1)
        XCTAssertNotEqual(rearranged.first?.region, .fullScreen)
        XCTAssertNotEqual(rearranged, original)

        let restored = await controller.placeWindows(launches, with: original)
        XCTAssertEqual(restored[accountID], .placed)
        let final = await controller.captureWindows(launches)
        let actual = try XCTUnwrap(final.first?.relativeFrame)
        let tolerance = 0.006
        XCTAssertEqual(actual.minX, expected.minX, accuracy: tolerance)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: tolerance)
        XCTAssertEqual(actual.width, expected.width, accuracy: tolerance)
        XCTAssertEqual(actual.height, expected.height, accuracy: tolerance)
    }

    private func makeControllerFixture(
        repository: MemoryWindowLayoutRepository = MemoryWindowLayoutRepository(),
        placer: RecordingWindowPlacer = RecordingWindowPlacer(),
        permissionManager: TestAccessibilityPermissionManager? = nil
    ) -> ControllerFixture {
        let resolvedPermissionManager = permissionManager ?? TestAccessibilityPermissionManager(isTrusted: true)
        let display = ConnectedDisplay(
            id: "display-1",
            name: "Test Display",
            frame: CGRect(x: 0, y: 0, width: 1400, height: 1000),
            visibleFrame: CGRect(x: 100, y: 50, width: 1200, height: 800),
            pixelWidth: 2800,
            pixelHeight: 2000,
            usablePixelWidth: 2400,
            usablePixelHeight: 1600
        )
        let snapshot = ConnectedDisplaySnapshot(
            displays: [display],
            accessibilityReferenceTop: 1000
        )
        let controller = WindowLayoutController(
            repository: repository,
            displayProvider: StaticDisplayProvider(snapshotValue: snapshot),
            placer: placer,
            permissionManager: resolvedPermissionManager
        )
        return ControllerFixture(controller: controller, display: display, snapshot: snapshot)
    }
}

private struct ControllerFixture {
    let controller: WindowLayoutController
    let display: ConnectedDisplay
    let snapshot: ConnectedDisplaySnapshot
}

private final class MemoryWindowLayoutRepository: WindowLayoutPersisting {
    private var assignments: [WindowLayoutAssignment] = []

    func load() -> [WindowLayoutAssignment] { assignments }
    func save(_ assignments: [WindowLayoutAssignment]) { self.assignments = assignments }
}

private struct StaticDisplayProvider: ConnectedDisplayProviding {
    let snapshotValue: ConnectedDisplaySnapshot

    @MainActor
    func snapshot() -> ConnectedDisplaySnapshot { snapshotValue }
}

private actor RecordingWindowPlacer: RobloxWindowPlacing {
    struct Request: Equatable {
        let processIdentifier: Int32
        let request: RobloxWindowPlacementRequest
    }

    private var requests: [Request] = []
    private let snapshot: RobloxWindowSnapshot?

    init(snapshot: RobloxWindowSnapshot? = nil) { self.snapshot = snapshot }

    func currentWindow(processIdentifier: Int32) async -> RobloxWindowSnapshot? { snapshot }

    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult {
        requests.append(Request(processIdentifier: processIdentifier, request: request))
        return .placed
    }

    func recordedRequests() -> [Request] { requests }
}

@MainActor
private final class TestAccessibilityPermissionManager: AccessibilityPermissionManaging {
    var trusted: Bool
    private let trustsAfterRequest: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool, trustsAfterRequest: Bool = true) {
        trusted = isTrusted
        self.trustsAfterRequest = trustsAfterRequest
    }

    func isTrusted() -> Bool { trusted }

    func requestAccess() {
        requestCount += 1
        if trustsAfterRequest { trusted = true }
    }
}

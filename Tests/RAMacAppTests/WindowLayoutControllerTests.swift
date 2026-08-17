import CoreGraphics
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class WindowLayoutControllerTests: XCTestCase {
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

    func testAdjustedPlacementDoesNotBecomeLaunchError() {
        let result = WindowPlacementResult.adjusted("Roblox kept this window at 800 × 628.")

        XCTAssertEqual(result.message, "Roblox kept this window at 800 × 628.")
        XCTAssertNil(result.requiresAttentionMessage)
    }

    func testOverlapDetectionMatchesSnapRegions() {
        XCTAssertTrue(WindowPlacementGeometry.regionsOverlap(.left, .topLeft))
        XCTAssertTrue(WindowPlacementGeometry.regionsOverlap(.wholeScreen, .bottomRight))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.left, .right))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.top, .bottom))
        XCTAssertFalse(WindowPlacementGeometry.regionsOverlap(.topLeft, .bottomLeft))
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

    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult {
        requests.append(Request(processIdentifier: processIdentifier, request: request))
        return .placed
    }

    func recordedRequests() -> [Request] { requests }
}

@MainActor
private final class TestAccessibilityPermissionManager: AccessibilityPermissionManaging {
    var trusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        trusted = isTrusted
    }

    func isTrusted() -> Bool { trusted }

    func requestAccess() {
        requestCount += 1
        trusted = true
    }
}

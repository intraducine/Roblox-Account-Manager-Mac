import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import RAMacCore

extension WindowPlacementRegion {
    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .top: return "Top"
        case .topRight: return "Top Right"
        case .left: return "Left"
        case .wholeScreen: return "Whole Screen"
        case .right: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom Right"
        }
    }

    var shortTitle: String {
        self == .wholeScreen ? "Whole" : title
    }

    var gridRow: Int {
        switch self {
        case .topLeft, .top, .topRight: return 0
        case .left, .wholeScreen, .right: return 1
        case .bottomLeft, .bottom, .bottomRight: return 2
        }
    }

    var gridColumn: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: return 0
        case .top, .wholeScreen, .bottom: return 1
        case .topRight, .right, .bottomRight: return 2
        }
    }
}

struct ConnectedDisplay: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let usablePixelWidth: Int
    let usablePixelHeight: Int
}

struct ConnectedDisplaySnapshot: Equatable, Sendable {
    let displays: [ConnectedDisplay]
    let accessibilityReferenceTop: CGFloat
}

enum WindowPlacementResult: Equatable, Sendable {
    case noAssignment
    case placed
    case adjusted(String)
    case permissionRequired
    case displayUnavailable(String)
    case failed(String)

    var message: String? {
        switch self {
        case .noAssignment, .placed:
            return nil
        case .adjusted(let message), .failed(let message):
            return message
        case .permissionRequired:
            return "Allow Window Control in System Settings so the app can arrange Roblox windows."
        case .displayUnavailable(let name):
            return "Connect \(name), then launch this account again."
        }
    }

    var requiresAttentionMessage: String? {
        switch self {
        case .noAssignment, .placed, .adjusted:
            return nil
        case .permissionRequired, .displayUnavailable, .failed:
            return message
        }
    }
}

enum WindowPlacementGeometry {
    static func frame(in visibleFrame: CGRect, region: WindowPlacementRegion) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2

        switch region {
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .top:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: halfHeight)
        case .topRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .left:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .wholeScreen:
            return visibleFrame
        case .right:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottom:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        }
    }

    static func accessibilityFrame(from appKitFrame: CGRect, referenceTop: CGFloat) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: referenceTop - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    static func anchoredAccessibilityFrame(
        size: CGSize,
        in availableFrame: CGRect,
        region: WindowPlacementRegion
    ) -> CGRect {
        let rawOrigin: CGPoint
        switch region {
        case .topLeft:
            rawOrigin = CGPoint(x: availableFrame.minX, y: availableFrame.minY)
        case .top:
            rawOrigin = CGPoint(x: availableFrame.midX - size.width / 2, y: availableFrame.minY)
        case .topRight:
            rawOrigin = CGPoint(x: availableFrame.maxX - size.width, y: availableFrame.minY)
        case .left:
            rawOrigin = CGPoint(x: availableFrame.minX, y: availableFrame.midY - size.height / 2)
        case .wholeScreen:
            rawOrigin = CGPoint(
                x: availableFrame.midX - size.width / 2,
                y: availableFrame.midY - size.height / 2
            )
        case .right:
            rawOrigin = CGPoint(
                x: availableFrame.maxX - size.width,
                y: availableFrame.midY - size.height / 2
            )
        case .bottomLeft:
            rawOrigin = CGPoint(x: availableFrame.minX, y: availableFrame.maxY - size.height)
        case .bottom:
            rawOrigin = CGPoint(
                x: availableFrame.midX - size.width / 2,
                y: availableFrame.maxY - size.height
            )
        case .bottomRight:
            rawOrigin = CGPoint(
                x: availableFrame.maxX - size.width,
                y: availableFrame.maxY - size.height
            )
        }

        let maximumX = max(availableFrame.minX, availableFrame.maxX - size.width)
        let maximumY = max(availableFrame.minY, availableFrame.maxY - size.height)
        let clampedOrigin = CGPoint(
            x: min(max(rawOrigin.x, availableFrame.minX), maximumX),
            y: min(max(rawOrigin.y, availableFrame.minY), maximumY)
        )
        return CGRect(origin: clampedOrigin, size: size)
    }

    static func regionsOverlap(_ first: WindowPlacementRegion, _ second: WindowPlacementRegion) -> Bool {
        let unitFrame = CGRect(x: 0, y: 0, width: 2, height: 2)
        let intersection = frame(in: unitFrame, region: first)
            .intersection(frame(in: unitFrame, region: second))
        return !intersection.isNull && intersection.width > 0.001 && intersection.height > 0.001
    }
}

protocol ConnectedDisplayProviding {
    @MainActor func snapshot() -> ConnectedDisplaySnapshot
}

struct SystemConnectedDisplayProvider: ConnectedDisplayProviding {
    @MainActor
    func snapshot() -> ConnectedDisplaySnapshot {
        let screens = NSScreen.screens
        let displays = screens.compactMap(makeDisplay)
        let primaryScreen = screens.first(where: { displayID(for: $0) == CGMainDisplayID() })
            ?? screens.first(where: { $0.frame.origin == .zero })
            ?? screens.first
        return ConnectedDisplaySnapshot(
            displays: displays,
            accessibilityReferenceTop: primaryScreen?.frame.maxY ?? 0
        )
    }

    @MainActor
    private func makeDisplay(_ screen: NSScreen) -> ConnectedDisplay? {
        guard let displayID = displayID(for: screen) else { return nil }
        let mode = CGDisplayCopyDisplayMode(displayID)
        let backingVisibleFrame = screen.convertRectToBacking(screen.visibleFrame)
        return ConnectedDisplay(
            id: String(displayID),
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor),
            pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor),
            usablePixelWidth: Int(backingVisibleFrame.width.rounded()),
            usablePixelHeight: Int(backingVisibleFrame.height.rounded())
        )
    }

    @MainActor
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(value.uint32Value)
    }
}

protocol WindowLayoutPersisting {
    func load() -> [WindowLayoutAssignment]
    func save(_ assignments: [WindowLayoutAssignment])
}

@MainActor
protocol AccessibilityPermissionManaging {
    func isTrusted() -> Bool
    func requestAccess()
}

struct SystemAccessibilityPermissionManager: AccessibilityPermissionManaging {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        guard !AXIsProcessTrusted() else { return }

        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for value in settingsURLs {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) { break }
        }
    }
}

struct UserDefaultsWindowLayoutRepository: WindowLayoutPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "windowLayoutAssignments.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [WindowLayoutAssignment] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WindowLayoutAssignment].self, from: data)) ?? []
    }

    func save(_ assignments: [WindowLayoutAssignment]) {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        defaults.set(data, forKey: key)
    }
}

protocol RobloxWindowPlacing: Sendable {
    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult
}

struct RobloxWindowPlacementRequest: Equatable, Sendable {
    let targetFrame: CGRect
    let availableFrame: CGRect
    let region: WindowPlacementRegion
}

actor AccessibilityRobloxWindowPlacer: RobloxWindowPlacing {
    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult {
        guard processIdentifier > 0 else {
            return .failed("The Roblox process could not be identified.")
        }
        guard AXIsProcessTrusted() else { return .permissionRequired }

        let application = AXUIElementCreateApplication(processIdentifier)
        for _ in 0..<60 {
            if Task.isCancelled { return .failed("Window placement was cancelled.") }
            if let window = firstWindow(of: application) {
                return await place(request, processIdentifier: processIdentifier, window: window)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return .failed("Roblox opened, but its window did not become available in time.")
    }

    private func firstWindow(of application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement] else { return nil }
        return windows.first
    }

    private func place(
        _ request: RobloxWindowPlacementRequest,
        processIdentifier: Int32,
        window: AXUIElement
    ) async -> WindowPlacementResult {
        var sizeSettable = DarwinBoolean(false)
        var positionSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable) == .success,
              sizeSettable.boolValue,
              positionSettable.boolValue else {
            return .failed("Roblox does not currently allow this window to be arranged.")
        }

        guard setSize(request.targetFrame.size, for: window) == .success,
              setPosition(request.targetFrame.origin, for: window) == .success,
              setSize(request.targetFrame.size, for: window) == .success else {
            return .failed("macOS could not apply the saved Roblox window layout.")
        }

        guard let settledFrame = await waitForSettledFrame(of: window) else {
            return .placed
        }

        let anchoredFrame = WindowPlacementGeometry.anchoredAccessibilityFrame(
            size: settledFrame.size,
            in: request.availableFrame,
            region: request.region
        )
        if frameDifference(settledFrame, anchoredFrame) > 2 {
            guard setPosition(anchoredFrame.origin, for: window) == .success else {
                return .failed("macOS could not move the Roblox window into its saved area.")
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let finalFrame = copyFrame(of: window),
               positionDifference(finalFrame.origin, anchoredFrame.origin) > 4 {
                return .adjusted(
                    "Roblox kept this window at \(pixelSize(settledFrame.size)) and moved it as close as possible to \(request.region.title.lowercased())."
                )
            }
        }

        if sizeDifference(settledFrame.size, request.targetFrame.size) > 4 {
            return .adjusted(
                "Roblox kept this window at \(pixelSize(settledFrame.size)). The app placed that size in \(request.region.title.lowercased())."
            )
        }
        return .placed
    }

    private func waitForSettledFrame(of window: AXUIElement) async -> CGRect? {
        var latestFrame: CGRect?
        var stableReads = 0

        for sampleIndex in 0..<30 {
            if Task.isCancelled { return latestFrame }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let frame = copyFrame(of: window) else { continue }
            if let latestFrame, frameDifference(frame, latestFrame) <= 2 {
                stableReads += 1
            } else {
                stableReads = 0
            }
            latestFrame = frame
            if sampleIndex >= 19, stableReads >= 2 { return frame }
        }
        return latestFrame
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) -> AXError {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func copyFrame(of window: AXUIElement) -> CGRect? {
        guard let size = copySize(of: window), let position = copyPosition(of: window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func frameDifference(_ first: CGRect, _ second: CGRect) -> CGFloat {
        sizeDifference(first.size, second.size) + positionDifference(first.origin, second.origin)
    }

    private func sizeDifference(_ first: CGSize, _ second: CGSize) -> CGFloat {
        abs(first.width - second.width) + abs(first.height - second.height)
    }

    private func positionDifference(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        abs(first.x - second.x) + abs(first.y - second.y)
    }

    private func pixelSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    private func copySize(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func copyPosition(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

}

@MainActor
final class WindowLayoutController: ObservableObject {
    @Published private(set) var displays: [ConnectedDisplay] = []
    @Published private(set) var assignments: [UUID: WindowLayoutAssignment] = [:]
    @Published private(set) var accessibilityPermissionGranted: Bool
    @Published var lastMessage: String?

    private let repository: any WindowLayoutPersisting
    private let displayProvider: any ConnectedDisplayProviding
    private let placer: any RobloxWindowPlacing
    private let permissionManager: any AccessibilityPermissionManaging
    private var accessibilityReferenceTop: CGFloat = 0

    init(
        repository: any WindowLayoutPersisting = UserDefaultsWindowLayoutRepository(),
        displayProvider: any ConnectedDisplayProviding = SystemConnectedDisplayProvider(),
        placer: any RobloxWindowPlacing = AccessibilityRobloxWindowPlacer(),
        permissionManager: (any AccessibilityPermissionManaging)? = nil
    ) {
        let resolvedPermissionManager = permissionManager ?? SystemAccessibilityPermissionManager()
        self.repository = repository
        self.displayProvider = displayProvider
        self.placer = placer
        self.permissionManager = resolvedPermissionManager
        accessibilityPermissionGranted = resolvedPermissionManager.isTrusted()
        assignments = Dictionary(uniqueKeysWithValues: repository.load().map { ($0.accountID, $0) })
        refreshDisplays()
    }

    func refreshDisplays() {
        let snapshot = displayProvider.snapshot()
        displays = snapshot.displays
        accessibilityReferenceTop = snapshot.accessibilityReferenceTop
        refreshAccessibilityPermission()
    }

    func requestAccessibilityPermission() {
        permissionManager.requestAccess()
        refreshAccessibilityPermission()
    }

    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = permissionManager.isTrusted()
    }

    func assignment(for accountID: UUID) -> WindowLayoutAssignment? {
        assignments[accountID]
    }

    func savedAssignments(for accountIDs: Set<UUID>) -> [WindowLayoutAssignment] {
        assignments.values
            .filter { accountIDs.contains($0.accountID) }
            .sorted { $0.accountID.uuidString < $1.accountID.uuidString }
    }

    func accountID(on displayID: String, region: WindowPlacementRegion) -> UUID? {
        assignments.values.first {
            $0.displayID == displayID && $0.region == region
        }?.accountID
    }

    func assign(accountID: UUID, to display: ConnectedDisplay, region: WindowPlacementRegion) {
        assignments = assignments.filter { existingAccountID, assignment in
            if existingAccountID == accountID { return false }
            guard assignment.displayID == display.id else { return true }
            return !WindowPlacementGeometry.regionsOverlap(assignment.region, region)
        }
        assignments[accountID] = WindowLayoutAssignment(
            accountID: accountID,
            displayID: display.id,
            displayName: display.name,
            displayPixelWidth: display.pixelWidth,
            displayPixelHeight: display.pixelHeight,
            region: region
        )
        persist()
        lastMessage = nil
    }

    func clear(accountID: UUID) {
        assignments[accountID] = nil
        persist()
    }

    func clearAll() {
        assignments.removeAll()
        persist()
    }

    func removeAssignmentsForMissingAccounts(validAccountIDs: Set<UUID>) {
        let filtered = assignments.filter { validAccountIDs.contains($0.key) }
        guard filtered.count != assignments.count else { return }
        assignments = filtered
        persist()
    }

    func placeWindow(accountID: UUID, processIdentifier: Int32) async -> WindowPlacementResult {
        let results = await placeWindows([(accountID, processIdentifier)])
        return results[accountID] ?? .noAssignment
    }

    func placeWindows(_ launches: [(accountID: UUID, processIdentifier: Int32)]) async -> [UUID: WindowPlacementResult] {
        await placeWindows(launches, with: Array(assignments.values))
    }

    func placeWindows(
        _ launches: [(accountID: UUID, processIdentifier: Int32)],
        with explicitAssignments: [WindowLayoutAssignment]
    ) async -> [UUID: WindowPlacementResult] {
        refreshDisplays()
        let assignmentsByAccount = Dictionary(
            explicitAssignments.map { ($0.accountID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let requests = launches.map { launch -> (UUID, Int32, RobloxWindowPlacementRequest?, WindowPlacementResult?) in
            guard let assignment = assignmentsByAccount[launch.accountID] else {
                return (launch.accountID, launch.processIdentifier, nil, .noAssignment)
            }
            guard let display = resolvedDisplay(for: assignment) else {
                return (
                    launch.accountID,
                    launch.processIdentifier,
                    nil,
                    .displayUnavailable(assignment.displayName)
                )
            }
            let appKitFrame = WindowPlacementGeometry.frame(in: display.visibleFrame, region: assignment.region)
            let accessibilityFrame = WindowPlacementGeometry.accessibilityFrame(
                from: appKitFrame,
                referenceTop: accessibilityReferenceTop
            )
            let availableFrame = WindowPlacementGeometry.accessibilityFrame(
                from: display.visibleFrame,
                referenceTop: accessibilityReferenceTop
            )
            return (
                launch.accountID,
                launch.processIdentifier,
                RobloxWindowPlacementRequest(
                    targetFrame: accessibilityFrame,
                    availableFrame: availableFrame,
                    region: assignment.region
                ),
                nil
            )
        }

        var results: [UUID: WindowPlacementResult] = [:]
        for request in requests {
            if let immediate = request.3 { results[request.0] = immediate }
        }

        let placer = self.placer
        await withTaskGroup(of: (UUID, WindowPlacementResult).self) { group in
            for request in requests {
                guard let placementRequest = request.2 else { continue }
                group.addTask {
                    (request.0, await placer.place(processIdentifier: request.1, request: placementRequest))
                }
            }
            for await (accountID, result) in group {
                results[accountID] = result
            }
        }

        let messages = results.values.compactMap(\.message)
        lastMessage = messages.first
        refreshAccessibilityPermission()
        return results
    }

    private func resolvedDisplay(for assignment: WindowLayoutAssignment) -> ConnectedDisplay? {
        if let exact = displays.first(where: { $0.id == assignment.displayID }) { return exact }
        return displays.first {
            $0.name == assignment.displayName
                && $0.pixelWidth == assignment.displayPixelWidth
                && $0.pixelHeight == assignment.displayPixelHeight
        }
    }

    private func persist() {
        repository.save(assignments.values.sorted { $0.accountID.uuidString < $1.accountID.uuidString })
    }
}

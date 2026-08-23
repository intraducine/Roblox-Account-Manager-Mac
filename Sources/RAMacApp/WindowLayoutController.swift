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
        case .wholeScreen: return "Fill Desktop"
        case .right: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom Right"
        case .fullScreen: return "Full Screen"
        }
    }

    var shortTitle: String {
        self == .wholeScreen ? "Fill" : title
    }

    var isNativeFullScreen: Bool { self == .fullScreen }

    static var windowedCases: [WindowPlacementRegion] {
        allCases.filter { !$0.isNativeFullScreen }
    }

    var gridRow: Int? {
        switch self {
        case .topLeft, .top, .topRight: return 0
        case .left, .wholeScreen, .right: return 1
        case .bottomLeft, .bottom, .bottomRight: return 2
        case .fullScreen: return nil
        }
    }

    var gridColumn: Int? {
        switch self {
        case .topLeft, .left, .bottomLeft: return 0
        case .top, .wholeScreen, .bottom: return 1
        case .topRight, .right, .bottomRight: return 2
        case .fullScreen: return nil
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
        case .wholeScreen, .fullScreen:
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
        case .wholeScreen, .fullScreen:
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
        if first.isNativeFullScreen || second.isNativeFullScreen { return false }
        let unitFrame = CGRect(x: 0, y: 0, width: 2, height: 2)
        let intersection = frame(in: unitFrame, region: first)
            .intersection(frame(in: unitFrame, region: second))
        return !intersection.isNull && intersection.width > 0.001 && intersection.height > 0.001
    }
}

enum WindowArrangementPlanner {
    static let maximumWindowedProfilesPerDisplay = 4

    static func automaticAssignments(
        accountIDs: [UUID],
        displays: [ConnectedDisplay]
    ) -> [WindowLayoutAssignment]? {
        guard !accountIDs.isEmpty else { return [] }
        guard !displays.isEmpty,
              accountIDs.count <= displays.count * maximumWindowedProfilesPerDisplay else { return nil }

        var remainingAccounts = accountIDs
        var assignments: [WindowLayoutAssignment] = []
        for (displayIndex, display) in displays.enumerated() where !remainingAccounts.isEmpty {
            let remainingDisplays = displays.count - displayIndex
            let count = min(
                maximumWindowedProfilesPerDisplay,
                Int(ceil(Double(remainingAccounts.count) / Double(remainingDisplays)))
            )
            let displayAccounts = Array(remainingAccounts.prefix(count))
            remainingAccounts.removeFirst(count)
            let regions = automaticRegions(count: displayAccounts.count, display: display)
            assignments.append(contentsOf: zip(displayAccounts, regions).map { accountID, region in
                assignment(accountID: accountID, display: display, region: region)
            })
        }
        return assignments
    }

    static func fullScreenAssignments(
        accountIDs: [UUID],
        displays: [ConnectedDisplay]
    ) -> [WindowLayoutAssignment] {
        guard !displays.isEmpty else { return [] }
        return accountIDs.enumerated().map { index, accountID in
            assignment(
                accountID: accountID,
                display: displays[index % displays.count],
                region: .fullScreen
            )
        }
    }

    private static func automaticRegions(
        count: Int,
        display: ConnectedDisplay
    ) -> [WindowPlacementRegion] {
        switch count {
        case 1:
            return [.wholeScreen]
        case 2:
            return display.visibleFrame.width >= display.visibleFrame.height
                ? [.left, .right]
                : [.top, .bottom]
        case 3:
            return display.visibleFrame.width >= display.visibleFrame.height
                ? [.left, .topRight, .bottomRight]
                : [.top, .bottomLeft, .bottomRight]
        default:
            return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    private static func assignment(
        accountID: UUID,
        display: ConnectedDisplay,
        region: WindowPlacementRegion
    ) -> WindowLayoutAssignment {
        WindowLayoutAssignment(
            accountID: accountID,
            displayID: display.id,
            displayName: display.name,
            displayPixelWidth: display.pixelWidth,
            displayPixelHeight: display.pixelHeight,
            region: region
        )
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
            "AXTrustedCheckOptionPrompt": true
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
    let screenFrame: CGRect
    let region: WindowPlacementRegion
}

actor AccessibilityRobloxWindowPlacer: RobloxWindowPlacing {
    private var nativeFullScreenAttribute: CFString { "AXFullScreen" as CFString }

    private enum PlacementAttempt {
        case retry
        case finished(WindowPlacementResult)
    }

    private enum NativeFullScreenState {
        case active
        case inactive
        case unknown
        case cancelled
    }

    private var fullScreenTransitionInProgress = false
    private var fullScreenWaiters: [CheckedContinuation<Void, Never>] = []

    func place(processIdentifier: Int32, request: RobloxWindowPlacementRequest) async -> WindowPlacementResult {
        guard processIdentifier > 0 else {
            return .failed("The Roblox process could not be identified.")
        }
        guard AXIsProcessTrusted() else { return .permissionRequired }

        let application = AXUIElementCreateApplication(processIdentifier)
        var foundWindow = false
        for _ in 0..<60 {
            if Task.isCancelled { return .failed("Window placement was cancelled.") }
            let windows = candidateWindows(of: application)
            foundWindow = foundWindow || !windows.isEmpty
            for window in windows {
                switch await attemptPlacement(
                    request,
                    window: window
                ) {
                case .retry:
                    continue
                case .finished(let result):
                    return result
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if foundWindow {
            return .failed("Roblox opened, but its game window did not become ready for arranging in time.")
        }
        return .failed("Roblox opened, but its window did not become available in time.")
    }

    private func candidateWindows(of application: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        var mainValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application,
            kAXMainWindowAttribute as CFString,
            &mainValue
        ) == .success,
           let mainValue,
           CFGetTypeID(mainValue) == AXUIElementGetTypeID() {
            let mainWindow = mainValue as! AXUIElement
            candidates.append(mainWindow)
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement] else { return candidates }
        for window in windows where !candidates.contains(where: { CFEqual($0, window) }) {
            candidates.append(window)
        }
        return candidates
    }

    private func attemptPlacement(
        _ request: RobloxWindowPlacementRequest,
        window: AXUIElement
    ) async -> PlacementAttempt {
        if request.region.isNativeFullScreen {
            if nativeFullScreenState(window, request: request) == .active {
                return .finished(.placed)
            }
            let canSetFullScreenState = isAttributeSettable(
                nativeFullScreenAttribute,
                on: window
            )
            let fullScreenButton = copyElement(
                attribute: kAXFullScreenButtonAttribute as CFString,
                from: window
            )
            guard canSetFullScreenState || fullScreenButton != nil else {
                return .retry
            }
            await acquireFullScreenTransition()
            let result = await enterNativeFullScreen(
                request,
                window: window,
                canSetFullScreenState: canSetFullScreenState,
                fullScreenButton: fullScreenButton
            )
            releaseFullScreenTransition()
            return .finished(result)
        }

        var sizeSettable = DarwinBoolean(false)
        var positionSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable) == .success,
              sizeSettable.boolValue,
              positionSettable.boolValue else {
            return .retry
        }

        guard setSize(request.targetFrame.size, for: window) == .success,
              setPosition(request.targetFrame.origin, for: window) == .success,
              setSize(request.targetFrame.size, for: window) == .success else {
            return .retry
        }

        guard let settledFrame = await waitForSettledFrame(of: window) else {
            return .retry
        }

        let anchoredFrame = WindowPlacementGeometry.anchoredAccessibilityFrame(
            size: settledFrame.size,
            in: request.availableFrame,
            region: request.region
        )
        if frameDifference(settledFrame, anchoredFrame) > 2 {
            guard setPosition(anchoredFrame.origin, for: window) == .success else {
                return .retry
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let finalFrame = copyFrame(of: window),
               positionDifference(finalFrame.origin, anchoredFrame.origin) > 4 {
                return .finished(.adjusted(
                    "Roblox kept this window at \(pixelSize(settledFrame.size)) and moved it as close as possible to \(request.region.title.lowercased())."
                ))
            }
        }

        if sizeDifference(settledFrame.size, request.targetFrame.size) > 4 {
            return .finished(.adjusted(
                "Roblox kept this window at \(pixelSize(settledFrame.size)). The app placed that size in \(request.region.title.lowercased())."
            ))
        }
        return .finished(.placed)
    }

    private func enterNativeFullScreen(
        _ request: RobloxWindowPlacementRequest,
        window: AXUIElement,
        canSetFullScreenState: Bool,
        fullScreenButton: AXUIElement?
    ) async -> WindowPlacementResult {
        if nativeFullScreenState(window, request: request) == .active {
            return .placed
        }

        var sizeSettable = DarwinBoolean(false)
        var positionSettable = DarwinBoolean(false)
        let canResize = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &sizeSettable
        ) == .success && sizeSettable.boolValue
        let canMove = AXUIElementIsAttributeSettable(
            window,
            kAXPositionAttribute as CFString,
            &positionSettable
        ) == .success && positionSettable.boolValue
        guard canResize, canMove else {
            return .failed("Roblox does not currently expose a window that macOS can move into full screen.")
        }

        guard setSize(request.targetFrame.size, for: window) == .success,
              setPosition(request.targetFrame.origin, for: window) == .success else {
            return .failed("macOS could not move Roblox onto the selected display before full screen.")
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        if canSetFullScreenState {
            return await requestNativeFullScreenState(window, request: request)
        }

        guard let fullScreenButton else {
            return .failed("Roblox does not expose a macOS full-screen action for this window.")
        }
        var button = fullScreenButton
        for attempt in 0..<2 {
            if nativeFullScreenState(window, request: request) == .active {
                return .placed
            }
            let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard pressResult == .success || pressResult == .cannotComplete else {
                return .failed("Roblox does not support the standard macOS full-screen action for this window.")
            }

            let state = await waitForNativeFullScreen(window, request: request)
            switch state {
            case .active:
                try? await Task.sleep(nanoseconds: 600_000_000)
                return .placed
            case .cancelled:
                return .failed("Full-screen placement was cancelled.")
            case .unknown:
                return .failed("macOS stopped exposing this Roblox window before the manager could confirm full screen. The manager did not press the control again because that could exit full screen.")
            case .inactive:
                break
            }

            if attempt == 0,
               let refreshedButton = copyElement(
                   attribute: kAXFullScreenButtonAttribute as CFString,
                   from: window
               ) {
                button = refreshedButton
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return .failed("macOS did not finish putting Roblox in full screen. Try this profile again after its window finishes loading.")
    }

    private func requestNativeFullScreenState(
        _ window: AXUIElement,
        request: RobloxWindowPlacementRequest
    ) async -> WindowPlacementResult {
        var latestSetResult = AXError.success
        for sampleIndex in 0..<75 {
            if Task.isCancelled {
                return .failed("Full-screen placement was cancelled.")
            }
            if nativeFullScreenState(window, request: request) == .active {
                try? await Task.sleep(nanoseconds: 600_000_000)
                return .placed
            }

            // Setting this state to true is idempotent. Repeating it cannot exit
            // full screen when the user changes apps, windows, or Spaces.
            if sampleIndex.isMultiple(of: 5) {
                latestSetResult = AXUIElementSetAttributeValue(
                    window,
                    nativeFullScreenAttribute,
                    kCFBooleanTrue
                )
                guard latestSetResult == .success || latestSetResult == .cannotComplete else {
                    return .failed("macOS rejected the full-screen request for this Roblox window.")
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if nativeFullScreenState(window, request: request) == .active {
            return .placed
        }
        if latestSetResult == .cannotComplete {
            return .failed("macOS kept this Roblox window busy and did not finish its background full-screen request.")
        }
        return .failed("macOS did not finish the background full-screen request for this Roblox window.")
    }

    private func waitForNativeFullScreen(
        _ window: AXUIElement,
        request: RobloxWindowPlacementRequest
    ) async -> NativeFullScreenState {
        var latestState = NativeFullScreenState.unknown
        for _ in 0..<50 {
            if Task.isCancelled { return .cancelled }
            try? await Task.sleep(nanoseconds: 200_000_000)
            let state = nativeFullScreenState(window, request: request)
            if state == .active { return .active }
            latestState = state
        }
        return latestState
    }

    private func nativeFullScreenState(
        _ window: AXUIElement,
        request: RobloxWindowPlacementRequest
    ) -> NativeFullScreenState {
        if let value = copyBoolean(attribute: nativeFullScreenAttribute, from: window) {
            return value ? .active : .inactive
        }

        guard let frame = copyFrame(of: window) else { return .unknown }
        var positionSettable = DarwinBoolean(true)
        let positionStatus = AXUIElementIsAttributeSettable(
            window,
            kAXPositionAttribute as CFString,
            &positionSettable
        )
        guard positionStatus == .success else { return .unknown }
        if !positionSettable.boolValue,
           frameMatchesScreen(frame, request.screenFrame)
            || frameDifference(frame, request.availableFrame) <= 16 {
            return .active
        }
        return .inactive
    }

    private func copyBoolean(attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success
            && settable.boolValue
    }

    private func acquireFullScreenTransition() async {
        if !fullScreenTransitionInProgress {
            fullScreenTransitionInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            fullScreenWaiters.append(continuation)
        }
    }

    private func releaseFullScreenTransition() {
        guard !fullScreenWaiters.isEmpty else {
            fullScreenTransitionInProgress = false
            return
        }
        let next = fullScreenWaiters.removeFirst()
        next.resume()
    }

    private func frameMatchesScreen(_ frame: CGRect, _ screenFrame: CGRect) -> Bool {
        frameDifference(frame, screenFrame) <= 16
    }

    private func copyElement(attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
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

    @discardableResult
    func arrangeAutomatically(accountIDs: [UUID]) -> Bool {
        guard let planned = WindowArrangementPlanner.automaticAssignments(
            accountIDs: accountIDs,
            displays: displays
        ) else {
            lastMessage = "Automatic arrangement supports up to four Roblox windows per connected display. Arrange the remaining profiles manually or use full screen."
            return false
        }
        let targetIDs = Set(accountIDs)
        assignments = assignments.filter { !targetIDs.contains($0.key) }
        for assignment in planned { assignments[assignment.accountID] = assignment }
        persist()
        lastMessage = nil
        return true
    }

    func makeFullScreen(accountIDs: [UUID]) {
        let planned = WindowArrangementPlanner.fullScreenAssignments(
            accountIDs: accountIDs,
            displays: displays
        )
        guard !planned.isEmpty || accountIDs.isEmpty else {
            lastMessage = "Connect a display before choosing full screen."
            return
        }
        let targetIDs = Set(accountIDs)
        assignments = assignments.filter { !targetIDs.contains($0.key) }
        for assignment in planned { assignments[assignment.accountID] = assignment }
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

    func placeWindow(
        accountID: UUID,
        processIdentifier: Int32,
        arrangement: WindowArrangementPolicy
    ) async -> WindowPlacementResult {
        switch arrangement {
        case .savedPlacements:
            return await placeWindow(accountID: accountID, processIdentifier: processIdentifier)
        case .custom(let assignments):
            let results = await placeWindows(
                [(accountID, processIdentifier)],
                with: assignments
            )
            return results[accountID] ?? .noAssignment
        case .unchanged:
            return .noAssignment
        }
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
                    screenFrame: WindowPlacementGeometry.accessibilityFrame(
                        from: display.frame,
                        referenceTop: accessibilityReferenceTop
                    ),
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

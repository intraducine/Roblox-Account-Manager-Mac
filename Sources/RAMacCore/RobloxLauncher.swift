import AppKit
import Darwin
import Foundation

public enum RobloxLaunchError: LocalizedError, Equatable {
    case invalidPlaceID
    case invalidServer
    case invalidURL
    case robloxNotInstalled
    case untrustedRobloxInstallation
    case accountAlreadyRunning
    case officialParallelUnavailable
    case copyFailed(String)
    case signingFailed(String)
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPlaceID:
            return "Enter a valid numeric place ID."
        case .invalidServer:
            return "Enter a valid job ID or private server link."
        case .invalidURL:
            return "The Roblox launch link could not be built."
        case .robloxNotInstalled:
            return "Roblox is not installed in Applications."
        case .untrustedRobloxInstallation:
            return "The Roblox app in Applications does not have a valid Roblox Corporation signature. Reinstall Roblox before using parallel launch."
        case .accountAlreadyRunning:
            return "This account already has a Roblox instance open. Stop it before launching it again."
        case .officialParallelUnavailable:
            return "The official Roblox app did not allow another client. Stop the running client or choose Modified Parallel Fallback."
        case .copyFailed(let detail):
            return "The managed Roblox copy could not be prepared. \(detail)"
        case .signingFailed(let detail):
            return "The managed Roblox copy could not be signed. \(detail)"
        case .openFailed:
            return "macOS could not open the isolated Roblox instance."
        }
    }
}

public enum RobloxLaunchMode: String, Codable, CaseIterable, Hashable, Sendable {
    case official
    case modifiedParallel

    public var title: String {
        switch self {
        case .official: return "Official Roblox"
        case .modifiedParallel: return "Modified Parallel Fallback"
        }
    }

    public var shortTitle: String {
        switch self {
        case .official: return "Official"
        case .modifiedParallel: return "Parallel Fallback"
        }
    }

    public var detail: String {
        switch self {
        case .official:
            return "Uses /Applications/Roblox.app without copying, editing, or signing it."
        case .modifiedParallel:
            return "Uses signed managed copies to work around Roblox's one-client limit."
        }
    }
}

public enum RobloxServerTarget: Equatable, Sendable {
    case publicServer
    case job(String)
    case privateServer(accessCode: String, linkCode: String)
}

public struct RobloxLaunchURLBuilder: Sendable {
    public init() {}

    public func makeURL(
        ticket: String,
        placeID: Int64,
        target: RobloxServerTarget = .publicServer,
        trackerID: String = Self.makeTrackerID(),
        launchTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> URL {
        guard placeID > 0 else { throw RobloxLaunchError.invalidPlaceID }

        let requestURL: String
        switch target {
        case .publicServer:
            requestURL = "https://assetgame.roblox.com/game/PlaceLauncher.ashx?request=RequestGame&browserTrackerId=\(trackerID)&placeId=\(placeID)&isPlayTogetherGame=false"
        case .job(let jobID):
            guard !jobID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RobloxLaunchError.invalidServer
            }
            requestURL = "https://assetgame.roblox.com/game/PlaceLauncher.ashx?request=RequestGameJob&browserTrackerId=\(trackerID)&placeId=\(placeID)&gameId=\(jobID)&isPlayTogetherGame=false"
        case .privateServer(let accessCode, let linkCode):
            guard !accessCode.isEmpty, !linkCode.isEmpty else { throw RobloxLaunchError.invalidServer }
            requestURL = "https://assetgame.roblox.com/game/PlaceLauncher.ashx?request=RequestPrivateGame&placeId=\(placeID)&accessCode=\(accessCode)&linkCode=\(linkCode)"
        }

        guard let encodedRequest = requestURL.addingPercentEncoding(withAllowedCharacters: Self.componentAllowed) else {
            throw RobloxLaunchError.invalidURL
        }
        let raw = "roblox-player:1+launchmode:play+gameinfo:\(ticket)+launchtime:\(launchTime)+placelauncherurl:\(encodedRequest)+browsertrackerid:\(trackerID)+robloxLocale:en_us+gameLocale:en_us+channel:+LaunchExp:InApp"
        guard let url = URL(string: raw) else { throw RobloxLaunchError.invalidURL }
        return url
    }

    public static func privateLinkCode(from input: String) -> String? {
        guard let components = URLComponents(string: input),
              let value = components.queryItems?.first(where: { $0.name == "privateServerLinkCode" })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    public static func makeTrackerID() -> String {
        String(format: "%012llu", UInt64.random(in: 100_000_000_000...999_999_999_999))
    }

    private static let componentAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

public struct ParallelRobloxInstance: Equatable, Sendable {
    public let accountID: UUID
    public let processIdentifier: Int32
    public let applicationURL: URL
}

public protocol ParallelRobloxLaunching: Sendable {
    func launch(_ url: URL, for accountID: UUID, mode: RobloxLaunchMode) async throws -> ParallelRobloxInstance
    func runningAccountIDs(from accountIDs: [UUID]) async -> Set<UUID>
    func stop(accountID: UUID) async -> Bool
    func removeStaleCopies() async
    func removePreparedCopy(accountID: UUID) async
}

private struct CommandFailure: LocalizedError {
    let output: String
    var errorDescription: String? { output.isEmpty ? "The system command failed." : output }
}

private struct ParallelProcessRecord: Codable {
    let processIdentifier: Int32
    let applicationPath: String
}

public actor ParallelRobloxLauncher {
    public static let officialApplicationURL = URL(fileURLWithPath: "/Applications/Roblox.app", isDirectory: true)
    public static let officialTeamIdentifier = "2CFABCH843"
    public static let parallelBundleIdentifier = "com.intraducine.RobloxAccountManager.player"
    public static let preparationVersion = 4

    public static let managedClientSettings: [String: Bool] = [
        "DFFlagEnableMacDesktopNotifications2": false,
        "FFlagEnableMacDesktopNotifications": false,
        "FFlagEnableMacMenuBar": false,
        "FFlagEnableMacMenuBar9": false
    ]

    private let fileManager: FileManager
    private let instancesRoot: URL
    private var officialLaunchInProgress = false

    public init(
        fileManager: FileManager = .default,
        instancesRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        if let instancesRoot {
            self.instancesRoot = instancesRoot
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.instancesRoot = applicationSupport
                .appendingPathComponent("Roblox Account Manager", isDirectory: true)
                .appendingPathComponent("Instances", isDirectory: true)
        }
    }

    public static func bundleIdentifier(for accountID: UUID) -> String {
        parallelBundleIdentifier
    }

    public static func patchedInfoPlist(
        _ data: Data,
        accountID: UUID,
        sourceBundleVersion: String? = nil
    ) throws -> Data {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard var info = object as? [String: Any] else { throw RobloxLaunchError.copyFailed("Its Info.plist is invalid.") }
        info["CFBundleIdentifier"] = bundleIdentifier(for: accountID)
        info["LSMultipleInstancesProhibited"] = false
        info["CFBundleDisplayName"] = "Roblox Parallel"
        info["RAMPreparationVersion"] = preparationVersion
        if let sourceBundleVersion {
            info["RAMSourceBundleVersion"] = sourceBundleVersion
        }
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    public func launch(
        _ url: URL,
        for accountID: UUID,
        mode: RobloxLaunchMode
    ) async throws -> ParallelRobloxInstance {
        guard fileManager.fileExists(atPath: Self.officialApplicationURL.path) else {
            throw RobloxLaunchError.robloxNotInstalled
        }
        if await isRunning(accountID: accountID) { throw RobloxLaunchError.accountAlreadyRunning }

        if mode == .official {
            while officialLaunchInProgress {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            officialLaunchInProgress = true
        }
        defer {
            if mode == .official { officialLaunchInProgress = false }
        }

        try verifyOfficialApplication()
        let applicationURL: URL
        switch mode {
        case .official:
            applicationURL = Self.officialApplicationURL
        case .modifiedParallel:
            applicationURL = try prepareCopy(for: accountID)
            // Older Roblox builds used this named semaphore. Current builds may not create it.
            _ = sem_unlink("/RobloxPlayerUniq")
        }

        let openedProcessIdentifier = try await open(url, with: applicationURL)
        let processIdentifier: Int32
        if mode == .official {
            processIdentifier = try await resolveOfficialProcessIdentifier(
                openedProcessIdentifier,
                excluding: accountID
            )
        } else {
            processIdentifier = openedProcessIdentifier
        }
        try fileManager.createDirectory(
            at: accountRootURL(for: accountID),
            withIntermediateDirectories: true
        )
        try writeProcessRecord(
            ParallelProcessRecord(
                processIdentifier: processIdentifier,
                applicationPath: applicationURL.standardizedFileURL.path
            ),
            for: accountID
        )
        return ParallelRobloxInstance(
            accountID: accountID,
            processIdentifier: processIdentifier,
            applicationURL: applicationURL
        )
    }

    public func runningAccountIDs(from accountIDs: [UUID]) async -> Set<UUID> {
        var result = Set<UUID>()
        for accountID in accountIDs where await isRunning(accountID: accountID) {
            result.insert(accountID)
        }
        return result
    }

    public func stop(accountID: UUID) async -> Bool {
        if readProcessRecord(for: accountID)?.applicationPath
            == Self.officialApplicationURL.standardizedFileURL.path {
            let stopped = await stopOfficialApplications()
            if stopped {
                try? fileManager.removeItem(at: processRecordURL(for: accountID))
            }
            return stopped
        }
        guard let application = await runningApplication(for: accountID) else { return true }
        _ = await MainActor.run { application.terminate() }

        if await waitUntilStopped(accountID: accountID, attempts: 20) {
            return true
        }

        if let remaining = await runningApplication(for: accountID) {
            _ = await MainActor.run { remaining.forceTerminate() }
        }
        return await waitUntilStopped(accountID: accountID, attempts: 10)
    }

    private func stopOfficialApplications() async -> Bool {
        let paths = Set([
            Self.officialApplicationURL.standardizedFileURL.path,
            Self.officialApplicationURL
                .appendingPathComponent("Contents/MacOS/RobloxMenuBar.app", isDirectory: true)
                .standardizedFileURL.path
        ])

        for _ in 0..<4 {
            let applications = await MainActor.run {
                NSWorkspace.shared.runningApplications.filter { application in
                    guard let path = application.bundleURL?.standardizedFileURL.path else { return false }
                    return paths.contains(path)
                }
            }
            if applications.isEmpty { return true }
            await MainActor.run {
                for application in applications { _ = application.terminate() }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                for application in applications where !application.isTerminated {
                    _ = application.forceTerminate()
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return await MainActor.run {
            !NSWorkspace.shared.runningApplications.contains { application in
                guard let path = application.bundleURL?.standardizedFileURL.path else { return false }
                return paths.contains(path)
            }
        }
    }

    public func removeStaleCopies() async {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: instancesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories {
            guard let accountID = UUID(uuidString: directory.lastPathComponent) else { continue }
            if !(await isRunning(accountID: accountID)) {
                try? fileManager.removeItem(at: processRecordURL(for: accountID))
            }
        }
    }

    public func removePreparedCopy(accountID: UUID) async {
        guard !(await isRunning(accountID: accountID)) else { return }
        try? removeOwnedItem(accountRootURL(for: accountID))
    }

    private func isRunning(accountID: UUID) async -> Bool {
        await runningApplication(for: accountID) != nil
    }

    private func runningApplication(for accountID: UUID) async -> NSRunningApplication? {
        guard let record = readProcessRecord(for: accountID) else { return nil }
        let officialPath = Self.officialApplicationURL.standardizedFileURL.path
        let managedPath = copyURL(for: accountID).standardizedFileURL.path
        guard record.applicationPath == officialPath || record.applicationPath == managedPath else {
            try? fileManager.removeItem(at: processRecordURL(for: accountID))
            return nil
        }
        let expectedPath = record.applicationPath
        let application = await MainActor.run { () -> NSRunningApplication? in
            guard let application = NSRunningApplication(processIdentifier: record.processIdentifier),
                  !application.isTerminated,
                  application.bundleURL?.standardizedFileURL.path == expectedPath else { return nil }
            return application
        }
        if application == nil {
            try? fileManager.removeItem(at: processRecordURL(for: accountID))
        }
        return application
    }

    private func recordedProcessIdentifiers(excluding accountID: UUID) async -> Set<Int32> {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: instancesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result = Set<Int32>()
        for directory in directories {
            guard let otherID = UUID(uuidString: directory.lastPathComponent),
                  otherID != accountID,
                  let application = await runningApplication(for: otherID) else { continue }
            result.insert(application.processIdentifier)
        }
        return result
    }

    private func resolveOfficialProcessIdentifier(
        _ openedProcessIdentifier: Int32,
        excluding accountID: UUID
    ) async throws -> Int32 {
        let officialPath = Self.officialApplicationURL.standardizedFileURL.path
        let recorded = await recordedProcessIdentifiers(excluding: accountID)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var stableProcessIdentifier: Int32?
        var stableSamples = 0

        for _ in 0..<35 {
            let candidates = await MainActor.run {
                NSWorkspace.shared.runningApplications.filter { application in
                    !application.isTerminated
                        && application.bundleURL?.standardizedFileURL.path == officialPath
                }
            }
            let candidate = candidates.first(where: {
                $0.processIdentifier == openedProcessIdentifier && !recorded.contains($0.processIdentifier)
            }) ?? candidates
                .filter({ !recorded.contains($0.processIdentifier) })
                .max(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) })

            if let candidate {
                if stableProcessIdentifier == candidate.processIdentifier {
                    stableSamples += 1
                } else {
                    stableProcessIdentifier = candidate.processIdentifier
                    stableSamples = 1
                }
                if stableSamples >= 10 { return candidate.processIdentifier }
            } else {
                stableProcessIdentifier = nil
                stableSamples = 0
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw RobloxLaunchError.officialParallelUnavailable
    }

    private func waitUntilStopped(accountID: UUID, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if !(await isRunning(accountID: accountID)) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return !(await isRunning(accountID: accountID))
    }

    private func prepareCopy(for accountID: UUID) throws -> URL {
        try fileManager.createDirectory(at: instancesRoot, withIntermediateDirectories: true)
        let accountRoot = accountRootURL(for: accountID)
        let copyURL = copyURL(for: accountID)
        let sourceVersion = try bundleVersion(at: Self.officialApplicationURL)

        if preparedCopyIsCurrent(copyURL, sourceVersion: sourceVersion) {
            return copyURL
        }

        try removeOwnedItem(accountRoot)
        try fileManager.createDirectory(at: accountRoot, withIntermediateDirectories: true)

        do {
            try run(
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: ["-cR", Self.officialApplicationURL.path, copyURL.path]
            )
            let infoURL = copyURL.appendingPathComponent("Contents/Info.plist")
            let patched = try Self.patchedInfoPlist(
                Data(contentsOf: infoURL),
                accountID: accountID,
                sourceBundleVersion: sourceVersion
            )
            try patched.write(to: infoURL, options: .atomic)
            try writeManagedClientSettings(to: copyURL)
            try removeManagedMenuBarHelper(from: copyURL)
        } catch let error as RobloxLaunchError {
            try? removeOwnedItem(accountRoot)
            throw error
        } catch {
            try? removeOwnedItem(accountRoot)
            throw RobloxLaunchError.copyFailed(error.localizedDescription)
        }

        do {
            let identity = codeSigningIdentity()
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: [
                    "--force",
                    "--deep",
                    "--preserve-metadata=entitlements,flags,runtime",
                    "--timestamp=none",
                    "--sign",
                    identity,
                    copyURL.path
                ]
            )
        } catch {
            try? removeOwnedItem(accountRoot)
            throw RobloxLaunchError.signingFailed(error.localizedDescription)
        }
        return copyURL
    }

    private func preparedCopyIsCurrent(_ copyURL: URL, sourceVersion: String) -> Bool {
        let infoURL = copyURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = object as? [String: Any],
              info["CFBundleIdentifier"] as? String == Self.parallelBundleIdentifier,
              info["RAMPreparationVersion"] as? Int == Self.preparationVersion,
              info["RAMSourceBundleVersion"] as? String == sourceVersion,
              info["LSMultipleInstancesProhibited"] as? Bool == false,
              managedClientSettingsAreCurrent(in: copyURL),
              !fileManager.fileExists(atPath: menuBarHelperURL(in: copyURL).path) else { return false }
        return (try? run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", copyURL.path]
        )) != nil
    }

    private func writeManagedClientSettings(to copyURL: URL) throws {
        let settingsDirectory = copyURL
            .appendingPathComponent("Contents/MacOS/ClientSettings", isDirectory: true)
        try fileManager.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: Self.managedClientSettings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: settingsDirectory.appendingPathComponent("ClientAppSettings.json"),
            options: .atomic
        )
    }

    private func managedClientSettingsAreCurrent(in copyURL: URL) -> Bool {
        let settingsURL = copyURL
            .appendingPathComponent("Contents/MacOS/ClientSettings/ClientAppSettings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let settings = object as? [String: Bool] else { return false }
        return settings == Self.managedClientSettings
    }

    private func removeManagedMenuBarHelper(from copyURL: URL) throws {
        let helperURL = menuBarHelperURL(in: copyURL)
        if fileManager.fileExists(atPath: helperURL.path) {
            try fileManager.removeItem(at: helperURL)
        }
    }

    private func menuBarHelperURL(in copyURL: URL) -> URL {
        copyURL.appendingPathComponent(
            "Contents/MacOS/RobloxMenuBar.app",
            isDirectory: true
        )
    }

    private func bundleVersion(at applicationURL: URL) throws -> String {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let info = object as? [String: Any],
              let version = info["CFBundleVersion"] as? String,
              !version.isEmpty else {
            throw RobloxLaunchError.copyFailed("The installed Roblox version could not be read.")
        }
        return version
    }

    private func codeSigningIdentity() -> String {
        guard let output = try? run(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-identity", "-v", "-p", "codesigning"]
        ) else { return "-" }

        let preferredLabels = ["Developer ID Application", "Apple Development", "Mac Developer"]
        for label in preferredLabels {
            for line in output.split(separator: "\n") where line.contains(label) {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                if fields.count >= 2, fields[1].count == 40 {
                    return String(fields[1])
                }
            }
        }
        return "-"
    }

    private func accountRootURL(for accountID: UUID) -> URL {
        instancesRoot.appendingPathComponent(accountID.uuidString, isDirectory: true)
    }

    private func copyURL(for accountID: UUID) -> URL {
        accountRootURL(for: accountID).appendingPathComponent("Roblox.app", isDirectory: true)
    }

    private func processRecordURL(for accountID: UUID) -> URL {
        accountRootURL(for: accountID).appendingPathComponent("Process.json")
    }

    private func writeProcessRecord(_ record: ParallelProcessRecord, for accountID: UUID) throws {
        try JSONEncoder().encode(record).write(to: processRecordURL(for: accountID), options: .atomic)
    }

    private func readProcessRecord(for accountID: UUID) -> ParallelProcessRecord? {
        let url = processRecordURL(for: accountID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ParallelProcessRecord.self, from: data)
    }

    private func verifyOfficialApplication() throws {
        do {
            let output = try run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--verify", "--deep", "--strict", "--verbose=4", Self.officialApplicationURL.path]
            )
            let details = try run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["-d", "--verbose=4", Self.officialApplicationURL.path]
            )
            guard (output + details).contains("TeamIdentifier=\(Self.officialTeamIdentifier)") else {
                throw RobloxLaunchError.untrustedRobloxInstallation
            }
        } catch let error as RobloxLaunchError {
            throw error
        } catch {
            throw RobloxLaunchError.untrustedRobloxInstallation
        }
    }

    @discardableResult
    private func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw CommandFailure(output: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func open(_ url: URL, with applicationURL: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                configuration.allowsRunningApplicationSubstitution = false
                configuration.addsToRecentItems = false
                configuration.activates = true
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { application, error in
                    if error != nil || application == nil {
                        continuation.resume(throwing: RobloxLaunchError.openFailed)
                    } else {
                        continuation.resume(returning: application!.processIdentifier)
                    }
                }
            }
        }
    }

    private func removeOwnedItem(_ url: URL) throws {
        let root = instancesRoot.standardizedFileURL.path + "/"
        let candidate = url.standardizedFileURL.path
        guard candidate.hasPrefix(root) else {
            throw RobloxLaunchError.copyFailed("The instance path was outside the managed app data.")
        }
        if fileManager.fileExists(atPath: candidate) {
            try fileManager.removeItem(at: url)
        }
    }
}

extension ParallelRobloxLauncher: ParallelRobloxLaunching {}

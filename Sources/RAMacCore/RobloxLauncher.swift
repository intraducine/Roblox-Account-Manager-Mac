import AppKit
import Darwin
import Foundation

public enum RobloxLaunchError: LocalizedError, Equatable {
    case invalidPlaceID
    case invalidServer
    case unsupportedPrivateServerLink
    case invalidURL
    case robloxNotInstalled
    case untrustedRobloxInstallation
    case accountAlreadyRunning
    case officialParallelUnavailable
    case unmodifiedParallelUnavailable(String)
    case copyFailed(String)
    case signingFailed(String)
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPlaceID:
            return "Enter a valid numeric place ID."
        case .invalidServer:
            return "Choose a valid server."
        case .unsupportedPrivateServerLink:
            return "This newer Roblox share link cannot select a saved account yet. Use an older private server link that contains privateServerLinkCode."
        case .invalidURL:
            return "The Roblox launch link could not be built."
        case .robloxNotInstalled:
            return "Roblox is not installed in Applications."
        case .untrustedRobloxInstallation:
            return "The Roblox app in Applications does not have a valid Roblox Corporation signature. Reinstall Roblox before using parallel launch."
        case .accountAlreadyRunning:
            return "This account already has a Roblox instance open. Stop it before launching it again."
        case .officialParallelUnavailable:
            return "The official Roblox app did not allow another client. Stop the running client or choose Unmodified Parallel."
        case .unmodifiedParallelUnavailable(let detail):
            return "The unmodified Roblox client could not start. \(detail)"
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
    case unmodifiedParallel
    case official
    case modifiedParallel

    public var title: String {
        switch self {
        case .unmodifiedParallel: return "Unmodified Parallel"
        case .official: return "Official Roblox"
        case .modifiedParallel: return "Modified Parallel Fallback"
        }
    }

    public var shortTitle: String {
        switch self {
        case .unmodifiedParallel: return "Unmodified"
        case .official: return "Official"
        case .modifiedParallel: return "Parallel Fallback"
        }
    }

    public var detail: String {
        switch self {
        case .unmodifiedParallel:
            return "Runs byte-identical Roblox copies with Roblox's original signature."
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
              isRobloxHost(components.host),
              let value = components.queryItems?.first(where: { $0.name == "privateServerLinkCode" })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    public static func privateShareCode(from input: String) -> String? {
        guard let components = URLComponents(string: input),
              isRobloxHost(components.host),
              components.path.lowercased() == "/share",
              components.queryItems?.first(where: { $0.name.lowercased() == "type" })?.value?.lowercased() == "server",
              let value = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    private static func isRobloxHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "roblox.com" || host.hasSuffix(".roblox.com")
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

private struct UnmodifiedCopyManifest: Codable {
    let formatVersion: Int
    let sourceBundleVersion: String
    let sourceCodeDirectoryHash: String
}

public actor ParallelRobloxLauncher {
    public static let officialApplicationURL = URL(fileURLWithPath: "/Applications/Roblox.app", isDirectory: true)
    public static let officialTeamIdentifier = "2CFABCH843"
    public static let parallelBundleIdentifier = "com.intraducine.RobloxAccountManager.player"
    public static let preparationVersion = 4
    public static let unmodifiedPreparationVersion = 1

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
        let openedProcessIdentifier: Int32
        switch mode {
        case .unmodifiedParallel:
            applicationURL = try prepareUnmodifiedCopy(for: accountID)
            openedProcessIdentifier = try await launchUnmodified(url, with: applicationURL)
        case .official:
            applicationURL = Self.officialApplicationURL
            openedProcessIdentifier = try await open(url, with: applicationURL)
        case .modifiedParallel:
            applicationURL = try prepareCopy(for: accountID)
            // Older Roblox builds used this named semaphore. Current builds may not create it.
            _ = sem_unlink("/RobloxPlayerUniq")
            openedProcessIdentifier = try await open(url, with: applicationURL)
        }

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
        for accountID in accountIDs {
            if await isRunning(accountID: accountID) {
                result.insert(accountID)
            }
            _ = await stopManagedHelpers(for: accountID)
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
        guard let record = validProcessRecord(for: accountID) else {
            try? fileManager.removeItem(at: processRecordURL(for: accountID))
            return await stopManagedHelpers(for: accountID)
        }
        let mainExecutablePath = canonicalPath(
            URL(fileURLWithPath: record.applicationPath, isDirectory: true)
                .appendingPathComponent("Contents/MacOS/RobloxPlayer")
                .path
        )
        for attempt in 0..<8 {
            _ = await stopManagedHelpers(for: accountID)
            let matchingProcesses = runningProcessTable().filter { $0.value == mainExecutablePath }
            if matchingProcesses.isEmpty {
                try? fileManager.removeItem(at: processRecordURL(for: accountID))
                return await stopManagedHelpers(for: accountID)
            }
            let signal = attempt < 4 ? SIGTERM : SIGKILL
            for processIdentifier in matchingProcesses.keys {
                _ = kill(processIdentifier, signal)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let mainStopped = runningProcessTable().values.allSatisfy { $0 != mainExecutablePath }
        let helpersStopped = await stopManagedHelpers(for: accountID)
        return mainStopped && helpersStopped
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
        guard let record = validProcessRecord(for: accountID),
              recordedProcessIsRunning(record) else {
            try? fileManager.removeItem(at: processRecordURL(for: accountID))
            return false
        }
        return true
    }

    private func validProcessRecord(for accountID: UUID) -> ParallelProcessRecord? {
        guard let record = readProcessRecord(for: accountID) else { return nil }
        let officialPath = Self.officialApplicationURL.standardizedFileURL.path
        let managedPath = copyURL(for: accountID).standardizedFileURL.path
        let unmodifiedPath = unmodifiedCopyURL(for: accountID).standardizedFileURL.path
        guard record.applicationPath == officialPath
            || record.applicationPath == managedPath
            || record.applicationPath == unmodifiedPath else {
            try? fileManager.removeItem(at: processRecordURL(for: accountID))
            return nil
        }
        return record
    }

    private func recordedProcessIsRunning(_ record: ParallelProcessRecord) -> Bool {
        let expectedExecutable = URL(fileURLWithPath: record.applicationPath, isDirectory: true)
            .appendingPathComponent("Contents/MacOS/RobloxPlayer")
            .path
        let canonicalExecutable = canonicalPath(expectedExecutable)
        return runningProcessTable()[record.processIdentifier] == canonicalExecutable
    }

    private func runningProcessTable() -> [Int32: String] {
        guard let output = try? run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,comm="]
        ) else { return [:] }
        var table: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, let processIdentifier = Int32(fields[0]) else { continue }
            let path = String(fields[1]).trimmingCharacters(in: .whitespaces)
            table[processIdentifier] = canonicalPath(path)
        }
        return table
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
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
                  let record = validProcessRecord(for: otherID),
                  recordedProcessIsRunning(record) else { continue }
            result.insert(record.processIdentifier)
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

    private func prepareUnmodifiedCopy(for accountID: UUID) throws -> URL {
        try fileManager.createDirectory(at: instancesRoot, withIntermediateDirectories: true)
        let destinationRoot = unmodifiedRootURL(for: accountID)
        let destination = unmodifiedCopyURL(for: accountID)
        let sourceVersion = try bundleVersion(at: Self.officialApplicationURL)
        let sourceHash = try codeDirectoryHash(at: Self.officialApplicationURL)

        if unmodifiedCopyIsCurrent(
            destination,
            sourceVersion: sourceVersion,
            sourceHash: sourceHash
        ) {
            return destination
        }

        try removeOwnedItem(destinationRoot)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        do {
            try run(
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: ["-cR", Self.officialApplicationURL.path, destination.path]
            )
            try verifyByteIdenticalCopy(destination)
            try writeUnmodifiedManifest(
                UnmodifiedCopyManifest(
                    formatVersion: Self.unmodifiedPreparationVersion,
                    sourceBundleVersion: sourceVersion,
                    sourceCodeDirectoryHash: sourceHash
                ),
                for: accountID
            )
        } catch let error as RobloxLaunchError {
            try? removeOwnedItem(destinationRoot)
            throw error
        } catch {
            try? removeOwnedItem(destinationRoot)
            throw RobloxLaunchError.copyFailed(error.localizedDescription)
        }
        return destination
    }

    private func unmodifiedCopyIsCurrent(
        _ copyURL: URL,
        sourceVersion: String,
        sourceHash: String
    ) -> Bool {
        guard let data = try? Data(contentsOf: unmodifiedManifestURL(for: copyURL)),
              let manifest = try? JSONDecoder().decode(UnmodifiedCopyManifest.self, from: data),
              manifest.formatVersion == Self.unmodifiedPreparationVersion,
              manifest.sourceBundleVersion == sourceVersion,
              manifest.sourceCodeDirectoryHash == sourceHash else { return false }
        do {
            try verifyByteIdenticalCopy(copyURL)
            return true
        } catch {
            return false
        }
    }

    private func verifyByteIdenticalCopy(_ copyURL: URL) throws {
        do {
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/diff"),
                arguments: ["-qr", Self.officialApplicationURL.path, copyURL.path]
            )
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--verify", "--deep", "--strict", "--verbose=4", copyURL.path]
            )
            let sourceHash = try codeDirectoryHash(at: Self.officialApplicationURL)
            let copyHash = try codeDirectoryHash(at: copyURL)
            guard sourceHash == copyHash else {
                throw RobloxLaunchError.copyFailed("The copy does not have the official Roblox code hash.")
            }
            let details = try codeSigningDetails(at: copyURL)
            guard details.contains("TeamIdentifier=\(Self.officialTeamIdentifier)") else {
                throw RobloxLaunchError.copyFailed("The copy does not have Roblox Corporation's original signature.")
            }
        } catch let error as RobloxLaunchError {
            throw error
        } catch {
            throw RobloxLaunchError.copyFailed("The copy differs from the installed Roblox app or its original signature is invalid.")
        }
    }

    private func writeUnmodifiedManifest(_ manifest: UnmodifiedCopyManifest, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: unmodifiedManifestURL(for: accountID), options: .atomic)
    }

    private func launchUnmodified(_ url: URL, with applicationURL: URL) async throws -> Int32 {
        let executableURL = applicationURL.appendingPathComponent("Contents/MacOS/RobloxPlayer")
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw RobloxLaunchError.unmodifiedParallelUnavailable("The RobloxPlayer executable is missing.")
        }

        let expectedExecutablePath = canonicalPath(executableURL.path)
        let existingProcessIdentifiers = Set(
            runningProcessTable().compactMap { processIdentifier, path in
                path == expectedExecutablePath ? processIdentifier : nil
            }
        )
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw RobloxLaunchError.unmodifiedParallelUnavailable("macOS could not start the exact app copy.")
        }

        let processIdentifier = process.processIdentifier
        do {
            try await sendLaunchURL(url, to: processIdentifier)
            return try await resolveUnmodifiedProcess(
                processIdentifier,
                executablePath: expectedExecutablePath,
                excluding: existingProcessIdentifiers
            )
        } catch {
            for candidate in runningProcessTable() where candidate.value == expectedExecutablePath {
                _ = kill(candidate.key, SIGTERM)
            }
            if let launchError = error as? RobloxLaunchError { throw launchError }
            throw RobloxLaunchError.unmodifiedParallelUnavailable(error.localizedDescription)
        }
    }

    private func sendLaunchURL(_ url: URL, to processIdentifier: Int32) async throws {
        let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: 0x4755524C,
            eventID: 0x4755524C,
            targetDescriptor: target,
            returnID: -1,
            transactionID: 0
        )
        event.setParam(
            NSAppleEventDescriptor(string: url.absoluteString),
            forKeyword: 0x2D2D2D2D
        )

        var lastError: Error?
        for _ in 0..<20 {
            guard kill(processIdentifier, 0) == 0 else {
                throw RobloxLaunchError.unmodifiedParallelUnavailable("Roblox closed before it received the launch request.")
            }
            do {
                _ = try event.sendEvent(options: .noReply, timeout: 2)
                return
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        throw RobloxLaunchError.unmodifiedParallelUnavailable(
            lastError?.localizedDescription ?? "Roblox did not accept the launch request."
        )
    }

    private func resolveUnmodifiedProcess(
        _ startedProcessIdentifier: Int32,
        executablePath: String,
        excluding existingProcessIdentifiers: Set<Int32>
    ) async throws -> Int32 {
        var stableProcessIdentifier: Int32?
        var stableSamples = 0
        for _ in 0..<50 {
            let candidates = runningProcessTable()
                .filter { $0.value == executablePath && !existingProcessIdentifiers.contains($0.key) }
                .map(\.key)
            let candidate = candidates.contains(startedProcessIdentifier)
                ? startedProcessIdentifier
                : candidates.max()
            if candidate == stableProcessIdentifier, candidate != nil {
                stableSamples += 1
                if stableSamples >= 8 { return candidate! }
            } else {
                stableProcessIdentifier = candidate
                stableSamples = candidate == nil ? 0 : 1
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw RobloxLaunchError.unmodifiedParallelUnavailable("Roblox did not remain open after launch.")
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

    private func unmodifiedRootURL(for accountID: UUID) -> URL {
        accountRootURL(for: accountID).appendingPathComponent("Unmodified", isDirectory: true)
    }

    private func unmodifiedCopyURL(for accountID: UUID) -> URL {
        unmodifiedRootURL(for: accountID).appendingPathComponent("Roblox.app", isDirectory: true)
    }

    private func unmodifiedManifestURL(for accountID: UUID) -> URL {
        unmodifiedRootURL(for: accountID).appendingPathComponent("Manifest.json")
    }

    private func unmodifiedManifestURL(for copyURL: URL) -> URL {
        copyURL.deletingLastPathComponent().appendingPathComponent("Manifest.json")
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
            let details = try codeSigningDetails(at: Self.officialApplicationURL)
            guard (output + details).contains("TeamIdentifier=\(Self.officialTeamIdentifier)") else {
                throw RobloxLaunchError.untrustedRobloxInstallation
            }
        } catch let error as RobloxLaunchError {
            throw error
        } catch {
            throw RobloxLaunchError.untrustedRobloxInstallation
        }
    }

    private func codeSigningDetails(at applicationURL: URL) throws -> String {
        try run(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["-d", "--verbose=4", applicationURL.path]
        )
    }

    private func codeDirectoryHash(at applicationURL: URL) throws -> String {
        let details = try codeSigningDetails(at: applicationURL)
        guard let line = details.split(separator: "\n").first(where: { $0.hasPrefix("CDHash=") }) else {
            throw RobloxLaunchError.untrustedRobloxInstallation
        }
        return String(line.dropFirst("CDHash=".count))
    }

    private func stopManagedHelpers(for accountID: UUID) async -> Bool {
        let helperExecutables = Set([
            copyURL(for: accountID),
            unmodifiedCopyURL(for: accountID)
        ].map {
            canonicalPath(
                menuBarHelperURL(in: $0)
                    .appendingPathComponent("Contents/MacOS/RobloxMenuBar")
                    .path
            )
        })
        for attempt in 0..<6 {
            let matching = runningProcessTable().filter { helperExecutables.contains($0.value) }
            if matching.isEmpty { return true }
            let signal = attempt < 3 ? SIGTERM : SIGKILL
            for processIdentifier in matching.keys {
                _ = kill(processIdentifier, signal)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return runningProcessTable().values.allSatisfy { !helperExecutables.contains($0) }
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

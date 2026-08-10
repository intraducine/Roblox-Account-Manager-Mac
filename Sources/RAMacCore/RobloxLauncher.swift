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
        case .copyFailed(let detail):
            return "The temporary Roblox copy could not be prepared. \(detail)"
        case .signingFailed(let detail):
            return "The temporary Roblox copy could not be signed. \(detail)"
        case .openFailed:
            return "macOS could not open the isolated Roblox instance."
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
    func launch(_ url: URL, for accountID: UUID) async throws -> ParallelRobloxInstance
    func runningAccountIDs(from accountIDs: [UUID]) async -> Set<UUID>
    func stop(accountID: UUID) async -> Bool
    func removeStaleCopies() async
}

private struct CommandFailure: LocalizedError {
    let output: String
    var errorDescription: String? { output.isEmpty ? "The system command failed." : output }
}

public actor ParallelRobloxLauncher {
    public static let officialApplicationURL = URL(fileURLWithPath: "/Applications/Roblox.app", isDirectory: true)
    public static let officialTeamIdentifier = "2CFABCH843"

    private let fileManager: FileManager
    private let instancesRoot: URL

    public init(
        fileManager: FileManager = .default,
        instancesRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        if let instancesRoot {
            self.instancesRoot = instancesRoot
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.instancesRoot = caches
                .appendingPathComponent("Roblox Account Manager", isDirectory: true)
                .appendingPathComponent("Instances", isDirectory: true)
        }
    }

    public static func bundleIdentifier(for accountID: UUID) -> String {
        "com.intraducine.RobloxAccountManager.instance.\(accountID.uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    public static func patchedInfoPlist(_ data: Data, accountID: UUID) throws -> Data {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard var info = object as? [String: Any] else { throw RobloxLaunchError.copyFailed("Its Info.plist is invalid.") }
        info["CFBundleIdentifier"] = bundleIdentifier(for: accountID)
        info["LSMultipleInstancesProhibited"] = false
        info["CFBundleDisplayName"] = "Roblox Parallel"
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    public func launch(_ url: URL, for accountID: UUID) async throws -> ParallelRobloxInstance {
        guard fileManager.fileExists(atPath: Self.officialApplicationURL.path) else {
            throw RobloxLaunchError.robloxNotInstalled
        }
        if await isRunning(accountID: accountID) { throw RobloxLaunchError.accountAlreadyRunning }

        try verifyOfficialApplication()
        let copyURL = try prepareCopy(for: accountID)

        // Older Roblox builds used this named semaphore. Current builds may not create it.
        _ = sem_unlink("/RobloxPlayerUniq")

        let processIdentifier = try await open(url, with: copyURL)
        return ParallelRobloxInstance(
            accountID: accountID,
            processIdentifier: processIdentifier,
            applicationURL: copyURL
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
        let bundleIdentifier = Self.bundleIdentifier(for: accountID)
        let applications = await runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !applications.isEmpty else { return true }
        for application in applications {
            _ = await MainActor.run { application.terminate() }
        }

        if await waitUntilStopped(bundleIdentifier: bundleIdentifier, attempts: 20) {
            return true
        }

        // Only force-stop the account-specific bundle. The signed Roblox app in
        // /Applications and every other isolated account stay untouched.
        let remaining = await runningApplications(withBundleIdentifier: bundleIdentifier)
        for application in remaining {
            _ = await MainActor.run { application.forceTerminate() }
        }
        return await waitUntilStopped(bundleIdentifier: bundleIdentifier, attempts: 10)
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
                try? removeOwnedItem(directory)
            }
        }
    }

    private func isRunning(accountID: UUID) async -> Bool {
        let bundleIdentifier = Self.bundleIdentifier(for: accountID)
        return !(await runningApplications(withBundleIdentifier: bundleIdentifier)).isEmpty
    }

    private func runningApplications(withBundleIdentifier bundleIdentifier: String) async -> [NSRunningApplication] {
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        }
    }

    private func waitUntilStopped(bundleIdentifier: String, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if (await runningApplications(withBundleIdentifier: bundleIdentifier)).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return (await runningApplications(withBundleIdentifier: bundleIdentifier)).isEmpty
    }

    private func prepareCopy(for accountID: UUID) throws -> URL {
        try fileManager.createDirectory(at: instancesRoot, withIntermediateDirectories: true)
        let accountRoot = instancesRoot.appendingPathComponent(accountID.uuidString, isDirectory: true)
        try removeOwnedItem(accountRoot)
        try fileManager.createDirectory(at: accountRoot, withIntermediateDirectories: true)
        let copyURL = accountRoot.appendingPathComponent("Roblox.app", isDirectory: true)

        do {
            try run(
                executable: URL(fileURLWithPath: "/bin/cp"),
                arguments: ["-cR", Self.officialApplicationURL.path, copyURL.path]
            )
            let infoURL = copyURL.appendingPathComponent("Contents/Info.plist")
            let patched = try Self.patchedInfoPlist(Data(contentsOf: infoURL), accountID: accountID)
            try patched.write(to: infoURL, options: .atomic)
        } catch let error as RobloxLaunchError {
            try? removeOwnedItem(accountRoot)
            throw error
        } catch {
            try? removeOwnedItem(accountRoot)
            throw RobloxLaunchError.copyFailed(error.localizedDescription)
        }

        do {
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--force", "--deep", "--sign", "-", copyURL.path]
            )
        } catch {
            try? removeOwnedItem(accountRoot)
            throw RobloxLaunchError.signingFailed(error.localizedDescription)
        }
        return copyURL
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
            throw RobloxLaunchError.copyFailed("The instance path was outside the managed cache.")
        }
        if fileManager.fileExists(atPath: candidate) {
            try fileManager.removeItem(at: url)
        }
    }
}

extension ParallelRobloxLauncher: ParallelRobloxLaunching {}

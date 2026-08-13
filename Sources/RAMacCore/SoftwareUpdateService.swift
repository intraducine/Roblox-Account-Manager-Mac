import CryptoKit
import Foundation
import Security

public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let number = Int(part),
                  number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct SoftwareUpdateRelease: Equatable, Sendable {
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let archive: SoftwareUpdateAsset
    public let checksum: SoftwareUpdateAsset
}

public struct SoftwareUpdateAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let byteCount: Int
    public let digest: String
}

public enum SoftwareUpdateCheck: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case available(SoftwareUpdateRelease)
}

public struct PreparedSoftwareUpdate: Sendable {
    public let release: SoftwareUpdateRelease
    public let applicationURL: URL
    public let workspaceURL: URL
}

public enum SoftwareUpdateError: LocalizedError, Equatable {
    case invalidCurrentVersion
    case invalidRelease
    case missingReleaseFiles
    case unsafeDownloadAddress
    case downloadFailed
    case archiveTooLarge
    case checksumFailed
    case extractionFailed
    case invalidApplication
    case wrongSigningIdentity
    case installationNotAllowed
    case installationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return "The installed app version could not be read. Download the latest release manually."
        case .invalidRelease:
            return "The latest GitHub release is not a valid app update."
        case .missingReleaseFiles:
            return "The latest release does not include both the app ZIP and its checksum file."
        case .unsafeDownloadAddress:
            return "The release files did not come from the expected GitHub project."
        case .downloadFailed:
            return "The update could not be downloaded from GitHub. Check your connection and try again."
        case .archiveTooLarge:
            return "The update file is larger than this app allows. Download it manually if the release is trusted."
        case .checksumFailed:
            return "The downloaded update did not match its published checksum. Nothing was installed."
        case .extractionFailed:
            return "The update ZIP could not be opened. Nothing was installed."
        case .invalidApplication:
            return "The downloaded app has the wrong name, version, identifier, or processor support. Nothing was installed."
        case .wrongSigningIdentity:
            return "The downloaded app does not have the same verified signing identity as this app. Nothing was installed."
        case .installationNotAllowed:
            return "macOS did not allow this app to update itself. Move it to Applications, make sure you own the file, and try again."
        case .installationFailed:
            return "The update could not replace the current app. The previous version was restored."
        }
    }
}

public final class GitHubSoftwareUpdateService: NSObject, @unchecked Sendable {
    public static let repository = "intraducine/Roblox-Account-Manager-Mac"
    public static let applicationName = "Roblox Account Manager.app"
    public static let bundleIdentifier = "com.intraducine.RobloxAccountManager"

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/\(repository)/releases/latest"
    )!
    private static let maximumArchiveSize = 100 * 1_024 * 1_024
    private static let maximumChecksumSize = 4 * 1_024

    private let session: URLSession
    private let redirectDelegate: SoftwareUpdateRedirectDelegate?
    private let fileManager: FileManager

    public init(session: URLSession? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let delegate = SoftwareUpdateRedirectDelegate()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 180
            configuration.httpAdditionalHeaders = [
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2026-03-10",
                "User-Agent": "Roblox-Account-Manager-Mac/1.0.4"
            ]
            redirectDelegate = delegate
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
        super.init()
    }

    public func check(currentVersion: String) async throws -> SoftwareUpdateCheck {
        guard let installed = AppVersion(currentVersion) else {
            throw SoftwareUpdateError.invalidCurrentVersion
        }
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Roblox-Account-Manager-Mac/1.0.4", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count <= 1_000_000 else {
            throw SoftwareUpdateError.downloadFailed
        }
        let payload: GitHubReleasePayload
        do { payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data) }
        catch { throw SoftwareUpdateError.invalidRelease }
        guard !payload.draft,
              !payload.prerelease,
              let latest = AppVersion(payload.tagName),
              let pageURL = URL(string: payload.pageURL),
              pageURL.scheme == "https",
              pageURL.host == "github.com" else {
            throw SoftwareUpdateError.invalidRelease
        }
        guard latest > installed else {
            return .upToDate(currentVersion: currentVersion)
        }

        let archiveName = "Roblox-Account-Manager-for-Mac-\(latest).zip"
        let checksumName = "\(archiveName).sha256"
        guard let archivePayload = payload.assets.first(where: { $0.name == archiveName }),
              let checksumPayload = payload.assets.first(where: { $0.name == checksumName }),
              let archive = try asset(from: archivePayload, maximumSize: Self.maximumArchiveSize),
              let checksum = try asset(from: checksumPayload, maximumSize: Self.maximumChecksumSize) else {
            throw SoftwareUpdateError.missingReleaseFiles
        }
        return .available(SoftwareUpdateRelease(
            version: latest,
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Version \(latest)",
            notes: String((payload.body ?? "").prefix(50_000)),
            pageURL: pageURL,
            archive: archive,
            checksum: checksum
        ))
    }

    public func downloadAndPrepare(
        _ release: SoftwareUpdateRelease,
        currentApplicationURL: URL
    ) async throws -> PreparedSoftwareUpdate {
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("RAMac-Update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            async let archiveDownload = download(release.archive, maximumSize: Self.maximumArchiveSize)
            async let checksumDownload = download(release.checksum, maximumSize: Self.maximumChecksumSize)
            let (archiveData, checksumData) = try await (archiveDownload, checksumDownload)
            let actualDigest = Self.sha256(archiveData)
            let actualChecksumDigest = Self.sha256(checksumData)
            guard release.archive.digest == "sha256:\(actualDigest)",
                  release.checksum.digest == "sha256:\(actualChecksumDigest)",
                  let checksumText = String(data: checksumData, encoding: .utf8),
                  Self.checksum(in: checksumText, for: release.archive.name) == actualDigest else {
                throw SoftwareUpdateError.checksumFailed
            }

            let archiveURL = workspace.appendingPathComponent(release.archive.name)
            try archiveData.write(to: archiveURL, options: .atomic)
            let expandedURL = workspace.appendingPathComponent("Expanded", isDirectory: true)
            try fileManager.createDirectory(at: expandedURL, withIntermediateDirectories: true)
            guard Self.run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, expandedURL.path]) else {
                throw SoftwareUpdateError.extractionFailed
            }
            let candidateURL = expandedURL.appendingPathComponent(Self.applicationName, isDirectory: true)
            try validateApplication(candidateURL, release: release, currentApplicationURL: currentApplicationURL)
            return PreparedSoftwareUpdate(
                release: release,
                applicationURL: candidateURL,
                workspaceURL: workspace
            )
        } catch {
            try? fileManager.removeItem(at: workspace)
            throw error
        }
    }

    public func discard(_ prepared: PreparedSoftwareUpdate) {
        try? fileManager.removeItem(at: prepared.workspaceURL)
    }

    public func validateApplication(
        _ candidateURL: URL,
        release: SoftwareUpdateRelease,
        currentApplicationURL: URL
    ) throws {
        let plistURL = candidateURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              plist["CFBundleIdentifier"] as? String == Self.bundleIdentifier,
              let versionText = plist["CFBundleShortVersionString"] as? String,
              AppVersion(versionText) == release.version,
              let executableName = plist["CFBundleExecutable"] as? String,
              executableName == URL(fileURLWithPath: executableName).lastPathComponent,
              fileManager.isExecutableFile(
                atPath: candidateURL.appendingPathComponent("Contents/MacOS/\(executableName)").path
              ),
              Self.run(
                "/usr/bin/lipo",
                [candidateURL.appendingPathComponent("Contents/MacOS/\(executableName)").path,
                 "-verify_arch", "arm64", "x86_64"]
              ) else {
            throw SoftwareUpdateError.invalidApplication
        }
        do { try Self.verifyMutuallyCompatibleSignatures(currentApplicationURL, candidateURL) }
        catch { throw SoftwareUpdateError.wrongSigningIdentity }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func checksum(in text: String, for filename: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2,
              fields[0].count == 64,
              fields[0].allSatisfy({ $0.isHexDigit }),
              fields.dropFirst().joined(separator: " ").trimmingPrefix("*") == filename else {
            return nil
        }
        return fields[0].lowercased()
    }

    private func asset(from payload: GitHubAssetPayload, maximumSize: Int) throws -> SoftwareUpdateAsset? {
        guard payload.state == "uploaded",
              payload.size > 0,
              payload.size <= maximumSize,
              let url = URL(string: payload.downloadURL),
              Self.isExpectedReleaseURL(url),
              let digest = payload.digest?.lowercased(),
              digest.hasPrefix("sha256:"),
              digest.count == 71,
              digest.dropFirst(7).allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return SoftwareUpdateAsset(
            name: payload.name,
            downloadURL: url,
            byteCount: payload.size,
            digest: digest
        )
    }

    private func download(_ asset: SoftwareUpdateAsset, maximumSize: Int) async throws -> Data {
        guard asset.byteCount <= maximumSize,
              Self.isExpectedReleaseURL(asset.downloadURL) else {
            throw SoftwareUpdateError.unsafeDownloadAddress
        }
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Roblox-Account-Manager-Mac/1.0.4", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count == asset.byteCount,
              data.count <= maximumSize else {
            throw SoftwareUpdateError.downloadFailed
        }
        return data
    }

    private static func isExpectedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "github.com"
            && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    private static func verifyMutuallyCompatibleSignatures(_ firstURL: URL, _ secondURL: URL) throws {
        let first = try staticCode(at: firstURL)
        let second = try staticCode(at: secondURL)
        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        try check(second, flags: flags, requirement: nil)
        let firstRequirement = try designatedRequirement(for: first)
        let secondRequirement = try designatedRequirement(for: second)
        try check(second, flags: flags, requirement: firstRequirement)
        try check(first, flags: flags, requirement: secondRequirement)
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code else { throw SoftwareUpdateError.wrongSigningIdentity }
        return code
    }

    private static func designatedRequirement(for code: SecStaticCode) throws -> SecRequirement {
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { throw SoftwareUpdateError.wrongSigningIdentity }
        return requirement
    }

    private static func check(
        _ code: SecStaticCode,
        flags: SecCSFlags,
        requirement: SecRequirement?
    ) throws {
        var error: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error) == errSecSuccess else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public final class SoftwareUpdateInstaller: @unchecked Sendable {
    private let service: GitHubSoftwareUpdateService
    private let fileManager: FileManager

    public init(
        service: GitHubSoftwareUpdateService,
        fileManager: FileManager = .default
    ) {
        self.service = service
        self.fileManager = fileManager
    }

    public func install(
        _ prepared: PreparedSoftwareUpdate,
        replacing applicationURL: URL
    ) throws -> URL {
        let parentURL = applicationURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path) else {
            throw SoftwareUpdateError.installationNotAllowed
        }
        let stagedURL = parentURL.appendingPathComponent(
            ".RAMac-update-\(UUID().uuidString).app",
            isDirectory: true
        )
        let backupURL = parentURL.appendingPathComponent(
            ".\(applicationURL.lastPathComponent).previous",
            isDirectory: true
        )
        do {
            try fileManager.copyItem(at: prepared.applicationURL, to: stagedURL)
            try service.validateApplication(
                stagedURL,
                release: prepared.release,
                currentApplicationURL: applicationURL
            )
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: applicationURL, to: backupURL)
            do {
                try fileManager.moveItem(at: stagedURL, to: applicationURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: applicationURL)
                throw SoftwareUpdateError.installationFailed
            }
            return backupURL
        } catch let updateError as SoftwareUpdateError {
            try? fileManager.removeItem(at: stagedURL)
            throw updateError
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw SoftwareUpdateError.installationNotAllowed
        }
    }

    public func restorePreviousVersion(from backupURL: URL, to applicationURL: URL) throws {
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        if fileManager.fileExists(atPath: applicationURL.path) {
            try fileManager.removeItem(at: applicationURL)
        }
        try fileManager.moveItem(at: backupURL, to: applicationURL)
    }
}

private final class SoftwareUpdateRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme == "https",
              let host = url.host,
              host == "github.com"
                || host == "api.github.com"
                || host.hasSuffix(".githubusercontent.com") else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let pageURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case pageURL = "html_url"
    }
}

private struct GitHubAssetPayload: Decodable {
    let name: String
    let downloadURL: String
    let size: Int
    let digest: String?
    let state: String

    enum CodingKeys: String, CodingKey {
        case name, size, digest, state
        case downloadURL = "browser_download_url"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

import CryptoKit
import Foundation
import Security

@_silgen_name("SecTrustedApplicationCreateFromRequirement")
private func ramSecTrustedApplicationCreateFromRequirement(
    _ description: UnsafePointer<CChar>?,
    _ requirement: SecRequirement,
    _ application: UnsafeMutablePointer<SecTrustedApplication?>
) -> OSStatus

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
    public let publishedAt: Date?
    public let archive: SoftwareUpdateAsset
    public let checksum: SoftwareUpdateAsset
    public let signature: SoftwareUpdateAsset
}

public struct SoftwareUpdateHistoryEntry: Identifiable, Equatable, Sendable {
    public var id: String { version.description }

    public let version: AppVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let publishedAt: Date?
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
    case releaseSignatureFailed
    case extractionFailed
    case invalidApplication
    case wrongSigningIdentity
    case keychainMigrationFailed
    case installationNotAllowed
    case installationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return "The installed app version could not be read. Download the latest release manually."
        case .invalidRelease:
            return "GitHub did not return a valid final app release."
        case .missingReleaseFiles:
            return "The newest final release does not include the app ZIP, checksum, and update signature."
        case .unsafeDownloadAddress:
            return "The release files did not come from the expected GitHub project."
        case .downloadFailed:
            return "The update could not be downloaded from GitHub. Check your connection and try again."
        case .archiveTooLarge:
            return "The update file is larger than this app allows. Download it manually if the release is trusted."
        case .checksumFailed:
            return "The downloaded update did not match its published checksum. Nothing was installed."
        case .releaseSignatureFailed:
            return "The downloaded update did not have this project's verified update signature. Nothing was installed."
        case .extractionFailed:
            return "The update ZIP could not be opened. Nothing was installed."
        case .invalidApplication:
            return "The downloaded app has the wrong name, version, identifier, or processor support. Nothing was installed."
        case .wrongSigningIdentity:
            return "The downloaded app does not have an approved verified signing identity. Nothing was installed."
        case .keychainMigrationFailed:
            return "macOS could not prepare saved sign-ins and encrypted notes for this signing update. Nothing was installed. Unlock Keychain and try again."
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

    private static let releaseHistoryPageSize = 100
    private static let maximumReleaseHistoryPages = 10
    private static let maximumReleaseHistoryPageSize = 5 * 1_024 * 1_024
    private static let maximumArchiveSize = 100 * 1_024 * 1_024
    private static let maximumChecksumSize = 4 * 1_024
    private static let maximumSignatureSize = 1_024
    private static let projectCertificateMigrationVersion = AppVersion("1.1.2")!
    private static let expectedProjectCertificateSHA256Key = "RAMExpectedProjectCertificateSHA256"
    static let releaseSignaturePublicKey = Data(
        base64Encoded: "BH6LL3N1YNpQjRTACAKLI9UELoIyysGzQlULU+wVmH1ze0iBShCFvhrpPcpfLGsNCOmkGrq6ZBErg8lCMb6ktww="
    )!

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
                "User-Agent": "Roblox-Account-Manager-Mac/1.1.1"
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
        let payloads = try await releasePayloads()
        let finalReleases = payloads.compactMap { payload -> (AppVersion, GitHubReleasePayload)? in
            guard !payload.draft,
                  !payload.prerelease,
                  let version = AppVersion(payload.tagName),
                  Self.safeReleasePageURL(payload.pageURL) != nil else { return nil }
            return (version, payload)
        }
        guard let (latest, payload) = finalReleases.max(by: { $0.0 < $1.0 }),
              latest > installed else {
            return .upToDate(currentVersion: currentVersion)
        }

        guard let pageURL = Self.safeReleasePageURL(payload.pageURL) else {
            throw SoftwareUpdateError.invalidRelease
        }

        let archiveName = "Roblox-Account-Manager-for-Mac-\(latest).zip"
        let checksumName = "\(archiveName).sha256"
        let signatureName = "\(archiveName).sig"
        let archiveMatches = payload.assets.filter { $0.name == archiveName }
        let checksumMatches = payload.assets.filter { $0.name == checksumName }
        let signatureMatches = payload.assets.filter { $0.name == signatureName }
        guard archiveMatches.count == 1,
              checksumMatches.count == 1,
              signatureMatches.count == 1,
              let archivePayload = archiveMatches.first,
              let checksumPayload = checksumMatches.first,
              let signaturePayload = signatureMatches.first,
              let archive = try asset(from: archivePayload, maximumSize: Self.maximumArchiveSize),
              let checksum = try asset(from: checksumPayload, maximumSize: Self.maximumChecksumSize),
              let signature = try asset(from: signaturePayload, maximumSize: Self.maximumSignatureSize) else {
            throw SoftwareUpdateError.missingReleaseFiles
        }
        return .available(SoftwareUpdateRelease(
            version: latest,
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Version \(latest)",
            notes: String((payload.body ?? "").prefix(50_000)),
            pageURL: pageURL,
            publishedAt: Self.releaseDate(payload.publishedAt),
            archive: archive,
            checksum: checksum,
            signature: signature
        ))
    }

    public func releaseHistory() async throws -> [SoftwareUpdateHistoryEntry] {
        var entries: [SoftwareUpdateHistoryEntry] = []
        var seenVersions: Set<String> = []

        for payload in try await releasePayloads() {
            guard let entry = Self.historyEntry(from: payload),
                  seenVersions.insert(entry.id).inserted else { continue }
            entries.append(entry)
        }

        return entries.sorted {
            switch ($0.publishedAt, $1.publishedAt) {
            case let (left?, right?) where left != right:
                return left > right
            default:
                return $0.version > $1.version
            }
        }
    }

    private func releasePayloads() async throws -> [GitHubReleasePayload] {
        var payloads: [GitHubReleasePayload] = []
        for page in 1...Self.maximumReleaseHistoryPages {
            var components = URLComponents(
                string: "https://api.github.com/repos/\(Self.repository)/releases"
            )!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: String(Self.releaseHistoryPageSize)),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components.url else { throw SoftwareUpdateError.invalidRelease }
            let (data, response) = try await session.data(for: releaseRequest(url: url))
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  data.count <= Self.maximumReleaseHistoryPageSize else {
                throw SoftwareUpdateError.downloadFailed
            }

            let pagePayloads: [GitHubReleasePayload]
            do { pagePayloads = try JSONDecoder().decode([GitHubReleasePayload].self, from: data) }
            catch { throw SoftwareUpdateError.invalidRelease }

            payloads.append(contentsOf: pagePayloads)
            if pagePayloads.count < Self.releaseHistoryPageSize { break }
        }
        return payloads
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
            async let signatureDownload = download(release.signature, maximumSize: Self.maximumSignatureSize)
            let (archiveData, checksumData, signatureData) = try await (
                archiveDownload,
                checksumDownload,
                signatureDownload
            )
            let actualDigest = Self.sha256(archiveData)
            let actualChecksumDigest = Self.sha256(checksumData)
            let actualSignatureDigest = Self.sha256(signatureData)
            guard release.archive.digest == "sha256:\(actualDigest)",
                  release.checksum.digest == "sha256:\(actualChecksumDigest)",
                  release.signature.digest == "sha256:\(actualSignatureDigest)",
                  let checksumText = String(data: checksumData, encoding: .utf8),
                  Self.checksum(in: checksumText, for: release.archive.name) == actualDigest else {
                throw SoftwareUpdateError.checksumFailed
            }
            guard Self.verifyReleaseSignature(signatureData, for: archiveData) else {
                throw SoftwareUpdateError.releaseSignatureFailed
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
        do {
            try Self.verifySigningIdentity(
                currentApplicationURL,
                candidateURL,
                releaseVersion: release.version
            )
        }
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

    static func verifyReleaseSignature(
        _ signature: Data,
        for archive: Data,
        publicKey: Data = releaseSignaturePublicKey
    ) -> Bool {
        guard let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return key.isValidSignature(signature, for: archive)
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

    private func releaseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Roblox-Account-Manager-Mac/1.1.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func historyEntry(from payload: GitHubReleasePayload) -> SoftwareUpdateHistoryEntry? {
        guard !payload.draft,
              !payload.prerelease,
              let version = AppVersion(payload.tagName),
              let pageURL = safeReleasePageURL(payload.pageURL) else { return nil }
        return SoftwareUpdateHistoryEntry(
            version: version,
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Version \(version)",
            notes: String((payload.body ?? "").prefix(50_000)),
            pageURL: pageURL,
            publishedAt: releaseDate(payload.publishedAt)
        )
    }

    private static func safeReleasePageURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.host == "github.com",
              url.user == nil,
              url.password == nil,
              url.path.hasPrefix("/\(repository)/releases/") else { return nil }
        return url
    }

    private static func releaseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func download(_ asset: SoftwareUpdateAsset, maximumSize: Int) async throws -> Data {
        guard asset.byteCount <= maximumSize,
              Self.isExpectedReleaseURL(asset.downloadURL) else {
            throw SoftwareUpdateError.unsafeDownloadAddress
        }
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Roblox-Account-Manager-Mac/1.1.1", forHTTPHeaderField: "User-Agent")
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

    private static func verifySigningIdentity(
        _ currentURL: URL,
        _ candidateURL: URL,
        releaseVersion: AppVersion
    ) throws {
        if releaseVersion >= projectCertificateMigrationVersion {
            try verifyApplicationSignature(currentURL)
            let expectedCertificateSHA256 = try expectedProjectCertificateSHA256(in: currentURL)
            _ = try verifiedProjectRequirement(
                candidateURL,
                expectedCertificateSHA256: expectedCertificateSHA256
            )
        } else {
            try verifyMutuallyCompatibleSignatures(currentURL, candidateURL)
        }
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

    static func verifyApplicationSignature(_ applicationURL: URL) throws {
        let application = try staticCode(at: applicationURL)
        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        try check(application, flags: flags, requirement: nil)
    }

    static func isValidProjectCertificateSHA256(_ value: String) -> Bool {
        value.range(
            of: #"^[a-f0-9]{64}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func expectedProjectCertificateSHA256(in applicationURL: URL) throws -> String {
        let application = try staticCode(at: applicationURL)
        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        try check(application, flags: flags, requirement: nil)

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            application,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [CFString: Any],
        let plist = information[kSecCodeInfoPList] as? [String: Any],
        let fingerprint = plist[expectedProjectCertificateSHA256Key] as? String,
        isValidProjectCertificateSHA256(fingerprint) else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
        return fingerprint
    }

    static func verifiedProjectRequirement(
        _ candidateURL: URL,
        expectedCertificateSHA256: String
    ) throws -> SecRequirement {
        let candidate = try staticCode(at: candidateURL)
        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        try check(candidate, flags: flags, requirement: nil)

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            candidate,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [CFString: Any],
        let certificates = information[kSecCodeInfoCertificates] as? [SecCertificate],
        let leafCertificate = certificates.first else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
        let certificateData = SecCertificateCopyData(leafCertificate) as Data
        guard sha256(certificateData) == expectedCertificateSHA256 else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
        let requirement = try designatedRequirement(for: candidate)
        try check(candidate, flags: flags, requirement: requirement)
        return requirement
    }

    func prepareProtectedKeychainAccess(
        for candidateApplicationURL: URL,
        release: SoftwareUpdateRelease,
        currentApplicationURL: URL
    ) throws {
        guard release.version >= Self.projectCertificateMigrationVersion else { return }
        do {
            let expectedCertificateSHA256 = try Self.expectedProjectCertificateSHA256(
                in: currentApplicationURL
            )
            let requirement = try Self.verifiedProjectRequirement(
                candidateApplicationURL,
                expectedCertificateSHA256: expectedCertificateSHA256
            )
            try SoftwareUpdateKeychainAccessBridge.authorize(
                candidateRequirement: requirement
            )
        } catch {
            throw SoftwareUpdateError.keychainMigrationFailed
        }
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

enum SoftwareUpdateKeychainAccessBridge {
    private static let protectedItems: [(service: String, account: String)] = [
        ("com.intraducine.RobloxAccountManager.session", "sessions-v2"),
        ("com.intraducine.RobloxAccountManager.profile-notes", "notes-v1")
    ]

    static func authorize(
        candidateRequirement: SecRequirement,
        items: [(service: String, account: String)] = protectedItems
    ) throws {
        var currentApplication: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &currentApplication) == errSecSuccess,
              let currentApplication else {
            throw SoftwareUpdateError.keychainMigrationFailed
        }

        var candidateApplication: SecTrustedApplication?
        // A path-based trusted application can change between validation and the ACL update.
        // Bind access to the validated code requirement instead.
        let candidateStatus = "csreq://com.intraducine.RobloxAccountManager".withCString { description in
            ramSecTrustedApplicationCreateFromRequirement(
                description,
                candidateRequirement,
                &candidateApplication
            )
        }
        guard candidateStatus == errSecSuccess,
              let candidateApplication else {
            throw SoftwareUpdateError.keychainMigrationFailed
        }

        var access: SecAccess?
        let trustedApplications = [currentApplication, candidateApplication] as CFArray
        guard SecAccessCreate(
            "Roblox Account Manager saved data" as CFString,
            trustedApplications,
            &access
        ) == errSecSuccess,
        let access else {
            throw SoftwareUpdateError.keychainMigrationFailed
        }

        for item in items {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account
            ]
            let status = SecItemUpdate(
                query as CFDictionary,
                [kSecAttrAccess as String: access] as CFDictionary
            )
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SoftwareUpdateError.keychainMigrationFailed
            }
        }
    }
}

public final class SoftwareUpdateInstaller: @unchecked Sendable {
    private let fileManager: FileManager
    private let validateApplication: (
        _ candidateURL: URL,
        _ release: SoftwareUpdateRelease,
        _ currentApplicationURL: URL
    ) throws -> Void
    private let prepareProtectedKeychainAccess: (
        _ candidateURL: URL,
        _ release: SoftwareUpdateRelease,
        _ currentApplicationURL: URL
    ) throws -> Void

    public init(
        service: GitHubSoftwareUpdateService,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        validateApplication = { candidateURL, release, currentApplicationURL in
            try service.validateApplication(
                candidateURL,
                release: release,
                currentApplicationURL: currentApplicationURL
            )
        }
        prepareProtectedKeychainAccess = { candidateURL, release, currentApplicationURL in
            try service.prepareProtectedKeychainAccess(
                for: candidateURL,
                release: release,
                currentApplicationURL: currentApplicationURL
            )
        }
    }

    init(
        fileManager: FileManager = .default,
        validateApplication: @escaping (
            _ candidateURL: URL,
            _ release: SoftwareUpdateRelease,
            _ currentApplicationURL: URL
        ) throws -> Void,
        prepareProtectedKeychainAccess: @escaping (
            _ candidateURL: URL,
            _ release: SoftwareUpdateRelease,
            _ currentApplicationURL: URL
        ) throws -> Void
    ) {
        self.fileManager = fileManager
        self.validateApplication = validateApplication
        self.prepareProtectedKeychainAccess = prepareProtectedKeychainAccess
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
            try validateApplication(
                stagedURL,
                prepared.release,
                applicationURL
            )
            try prepareProtectedKeychainAccess(
                stagedURL,
                prepared.release,
                applicationURL
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
                try validateApplication(
                    applicationURL,
                    prepared.release,
                    backupURL
                )
            } catch {
                try? fileManager.removeItem(at: applicationURL)
                try? fileManager.moveItem(at: backupURL, to: applicationURL)
                if let updateError = error as? SoftwareUpdateError {
                    throw updateError
                }
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
    let publishedAt: String?
    let assets: [GitHubAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case pageURL = "html_url"
        case publishedAt = "published_at"
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

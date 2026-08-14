import CryptoKit
import Foundation
import Security
import XCTest
@testable import RAMacCore

final class SoftwareUpdateServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SoftwareUpdateURLProtocol.handler = nil
    }

    func testVersionComparisonUsesNumericParts() {
        XCTAssertLessThan(AppVersion("1.0.9")!, AppVersion("1.0.10")!)
        XCTAssertEqual(AppVersion("v1.0.3"), AppVersion("1.0.3.0"))
        XCTAssertNil(AppVersion("1.0.beta"))
        XCTAssertNil(AppVersion("1..3"))
    }

    func testUpdateCheckFindsExactReleaseFiles() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/repos/intraducine/Roblox-Account-Manager-Mac/releases")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "Roblox-Account-Manager-Mac/1.1.2"
            )
            return Self.response(request, "[\(Self.releaseJSON(version: "1.0.3"))]")
        }

        let result = try await makeService().check(currentVersion: "1.0.2")

        guard case .available(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(release.version, AppVersion("1.0.3"))
        XCTAssertEqual(release.publishedAt, ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z"))
        XCTAssertEqual(release.archive.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip")
        XCTAssertEqual(release.checksum.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip.sha256")
        XCTAssertEqual(release.signature.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip.sig")
    }

    func testUpdateCheckFindsHighestFinalReleaseEvenWhenItIsNotMarkedLatest() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            let releases = [
                Self.releaseJSON(version: "1.1.1"),
                Self.releaseJSON(version: "1.1.2"),
                Self.releaseJSON(version: "1.2.0", prerelease: true)
            ].joined(separator: ",")
            return Self.response(request, "[\(releases)]")
        }

        let result = try await makeService().check(currentVersion: "1.1.1")

        guard case .available(let release) = result else {
            return XCTFail("Expected the unmarked final update")
        }
        XCTAssertEqual(release.version, AppVersion("1.1.2"))
    }

    func testReleaseHistoryListsOnlyFinalProjectReleasesNewestFirst() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/repos/intraducine/Roblox-Account-Manager-Mac/releases")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "per_page" })?.value, "100")
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "page" })?.value, "1")
            let releases = [
                Self.releaseJSON(version: "1.0.3", publishedAt: "2026-08-10T12:00:00Z"),
                Self.releaseJSON(version: "1.0.5", prerelease: true),
                Self.releaseJSON(version: "1.0.4", publishedAt: "2026-08-13T12:00:00Z"),
                Self.releaseJSON(version: "1.0.6", draft: true),
                Self.releaseJSON(
                    version: "1.0.2",
                    pageURL: "https://github.com/another-project/releases/tag/v1.0.2"
                )
            ].joined(separator: ",")
            return Self.response(request, "[\(releases)]")
        }

        let history = try await makeService().releaseHistory()

        XCTAssertEqual(history.map(\.version), [AppVersion("1.0.4")!, AppVersion("1.0.3")!])
        XCTAssertEqual(history.first?.title, "Roblox Account Manager for Mac 1.0.4")
        XCTAssertEqual(history.first?.notes, "Update notes")
        XCTAssertEqual(
            history.first?.publishedAt,
            ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z")
        )
    }

    func testUpdateCheckDoesNotInstallAnOlderRelease() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            Self.response(request, "[\(Self.releaseJSON(version: "1.0.2"))]")
        }

        let result = try await makeService().check(currentVersion: "1.0.3")

        XCTAssertEqual(result, .upToDate(currentVersion: "1.0.3"))
    }

    func testUpdateCheckRejectsPrerelease() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            Self.response(request, "[\(Self.releaseJSON(version: "1.0.4", prerelease: true))]")
        }

        let result = try await makeService().check(currentVersion: "1.0.3")
        XCTAssertEqual(result, .upToDate(currentVersion: "1.0.3"))
    }

    func testChecksumParsingRequiresTheExpectedFilename() {
        let digest = String(repeating: "a", count: 64)
        XCTAssertEqual(
            GitHubSoftwareUpdateService.checksum(
                in: "\(digest)  Roblox-Account-Manager-for-Mac-1.0.3.zip\n",
                for: "Roblox-Account-Manager-for-Mac-1.0.3.zip"
            ),
            digest
        )
        XCTAssertNil(GitHubSoftwareUpdateService.checksum(
            in: "\(digest)  different.zip\n",
            for: "Roblox-Account-Manager-for-Mac-1.0.3.zip"
        ))
    }

    func testUpdateCheckRequiresReleaseSignatureAsset() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            Self.response(request, "[\(Self.releaseJSON(version: "1.0.3", includeSignature: false))]")
        }

        do {
            _ = try await makeService().check(currentVersion: "1.0.2")
            XCTFail("Expected a missing release files error")
        } catch let error as SoftwareUpdateError {
            XCTAssertEqual(error, .missingReleaseFiles)
        }
    }

    func testReleaseSignatureRejectsChangedArchiveOrSignature() throws {
        let privateKey = P256.Signing.PrivateKey()
        let archive = Data("official archive".utf8)
        let signature = try privateKey.signature(for: archive).derRepresentation

        XCTAssertTrue(GitHubSoftwareUpdateService.verifyReleaseSignature(
            signature,
            for: archive,
            publicKey: privateKey.publicKey.x963Representation
        ))
        XCTAssertFalse(GitHubSoftwareUpdateService.verifyReleaseSignature(
            signature,
            for: Data("changed archive".utf8),
            publicKey: privateKey.publicKey.x963Representation
        ))
        XCTAssertFalse(GitHubSoftwareUpdateService.verifyReleaseSignature(
            Data(signature.dropLast()),
            for: archive,
            publicKey: privateKey.publicKey.x963Representation
        ))
    }

    func testProjectCertificateFingerprintRequiresLowercaseSHA256() {
        XCTAssertTrue(GitHubSoftwareUpdateService.isValidProjectCertificateSHA256(
            String(repeating: "a", count: 64)
        ))
        XCTAssertFalse(GitHubSoftwareUpdateService.isValidProjectCertificateSHA256(
            String(repeating: "A", count: 64)
        ))
        XCTAssertFalse(GitHubSoftwareUpdateService.isValidProjectCertificateSHA256(
            String(repeating: "a", count: 63)
        ))
        XCTAssertFalse(GitHubSoftwareUpdateService.isValidProjectCertificateSHA256(
            String(repeating: "z", count: 64)
        ))
    }

    func testCurrentApplicationMetadataMustRemainInsideItsValidSignature() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAMac-Signed-App-Test-\(UUID().uuidString)", isDirectory: true)
        let applicationURL = workspace.appendingPathComponent("Roblox Account Manager.app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let executableURL = contentsURL.appendingPathComponent("MacOS/TestApp")
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.intraducine.RobloxAccountManager",
            "CFBundleExecutable": "TestApp",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.1.1",
            "RAMExpectedProjectCertificateSHA256": String(repeating: "a", count: 64)
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: infoURL)
        XCTAssertEqual(Self.run("/usr/bin/codesign", [
            "--force", "--deep", "--sign", "-", applicationURL.path
        ]), 0)

        XCTAssertNoThrow(try GitHubSoftwareUpdateService.verifyApplicationSignature(applicationURL))
        var changedInfo = info
        changedInfo["RAMExpectedProjectCertificateSHA256"] = String(repeating: "b", count: 64)
        try PropertyListSerialization.data(fromPropertyList: changedInfo, format: .xml, options: 0)
            .write(to: infoURL, options: .atomic)
        XCTAssertThrowsError(try GitHubSoftwareUpdateService.verifyApplicationSignature(applicationURL))
    }

    func testKeychainBridgeAuthorizesTheCandidateTool() throws {
        guard ProcessInfo.processInfo.environment["RAM_RUN_KEYCHAIN_BRIDGE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RAM_RUN_KEYCHAIN_BRIDGE_INTEGRATION=1 for the macOS Keychain ACL test.")
        }
        let service = "com.intraducine.RobloxAccountManager.update-bridge-tests.\(UUID().uuidString)"
        let account = "temporary-item"
        let secret = "temporary-bridge-secret"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        defer { SecItemDelete(query as CFDictionary) }

        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)

        try SoftwareUpdateKeychainAccessBridge.authorize(
            candidateRequirement: try Self.designatedRequirement(at: "/usr/bin/security"),
            items: [(service, account)]
        )

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            secret
        )
    }

    func testKeychainBridgeTrustRequirementRejectsDifferentCodeAtTheSameBoundary() throws {
        let securityRequirement = try Self.designatedRequirement(at: "/usr/bin/security")
        var otherCode: SecStaticCode?
        XCTAssertEqual(
            SecStaticCodeCreateWithPath(
                URL(fileURLWithPath: "/usr/bin/codesign") as CFURL,
                SecCSFlags(),
                &otherCode
            ),
            errSecSuccess
        )
        let status = SecStaticCodeCheckValidity(
            try XCTUnwrap(otherCode),
            SecCSFlags(rawValue: kSecCSStrictValidate),
            securityRequirement
        )
        XCTAssertNotEqual(status, errSecSuccess)
    }

    func testInstallerRejectsAReplacementAfterPreparationAndRestoresCurrentApp() throws {
        let fixture = try Self.makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspaceURL) }
        var validationCount = 0
        let installer = SoftwareUpdateInstaller(
            validateApplication: { candidateURL, _, _ in
                validationCount += 1
                let marker = try String(
                    contentsOf: candidateURL.appendingPathComponent("marker"),
                    encoding: .utf8
                )
                guard marker == "candidate" else {
                    throw SoftwareUpdateError.wrongSigningIdentity
                }
            },
            prepareProtectedKeychainAccess: { stagedURL, _, _ in
                try FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.createDirectory(
                    at: stagedURL,
                    withIntermediateDirectories: true
                )
                try Data("replacement".utf8).write(
                    to: stagedURL.appendingPathComponent("marker")
                )
            }
        )

        XCTAssertThrowsError(
            try installer.install(fixture.prepared, replacing: fixture.currentURL)
        ) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .wrongSigningIdentity)
        }
        XCTAssertEqual(validationCount, 2)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.currentURL.appendingPathComponent("marker"),
                encoding: .utf8
            ),
            "current"
        )
    }

    func testInstallerKeepsTheValidatedReplacementAndBackup() throws {
        let fixture = try Self.makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspaceURL) }
        var validationCount = 0
        let installer = SoftwareUpdateInstaller(
            validateApplication: { candidateURL, _, _ in
                validationCount += 1
                XCTAssertEqual(
                    try String(
                        contentsOf: candidateURL.appendingPathComponent("marker"),
                        encoding: .utf8
                    ),
                    "candidate"
                )
            },
            prepareProtectedKeychainAccess: { _, _, _ in }
        )

        let backupURL = try installer.install(fixture.prepared, replacing: fixture.currentURL)

        XCTAssertEqual(validationCount, 2)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.currentURL.appendingPathComponent("marker"),
                encoding: .utf8
            ),
            "candidate"
        )
        XCTAssertEqual(
            try String(
                contentsOf: backupURL.appendingPathComponent("marker"),
                encoding: .utf8
            ),
            "current"
        )
    }

    func testSHA256UsesTheStandardDigest() {
        XCTAssertEqual(
            GitHubSoftwareUpdateService.sha256(Data("hello".utf8)),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testLiveReleaseDownloadAndReplacementWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RAM_RUN_UPDATE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RAM_RUN_UPDATE_INTEGRATION=1 after publishing the release assets.")
        }
        guard let sourcePath = ProcessInfo.processInfo.environment["RAM_UPDATE_CURRENT_APP"],
              FileManager.default.fileExists(atPath: sourcePath) else {
            throw XCTSkip("Set RAM_UPDATE_CURRENT_APP to the signed version 1.0.2 app.")
        }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAMac-Live-Update-Test-\(UUID().uuidString)", isDirectory: true)
        let currentURL = workspace.appendingPathComponent("Roblox Account Manager.app", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: currentURL)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let service = GitHubSoftwareUpdateService()
        let check = try await service.check(currentVersion: "1.0.2")
        guard case .available(let release) = check else {
            return XCTFail("Expected the published version 1.1.0 release")
        }
        XCTAssertEqual(release.version, AppVersion("1.1.0"))

        let prepared = try await service.downloadAndPrepare(
            release,
            currentApplicationURL: currentURL
        )
        defer { service.discard(prepared) }
        let installer = SoftwareUpdateInstaller(service: service)
        let backupURL = try installer.install(prepared, replacing: currentURL)

        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.1.0")
        XCTAssertEqual(Self.bundleVersion(at: backupURL), "1.0.2")
        try installer.restorePreviousVersion(from: backupURL, to: currentURL)
        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.0.2")
    }

    func testLocalSigningBridgeWhenEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RAM_RUN_SIGNING_BRIDGE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RAM_RUN_SIGNING_BRIDGE_INTEGRATION=1 with local bridge app paths.")
        }
        guard let currentPath = environment["RAM_SIGNING_BRIDGE_CURRENT_APP"],
              let candidatePath = environment["RAM_SIGNING_BRIDGE_CANDIDATE_APP"] else {
            return XCTFail("Set RAM_SIGNING_BRIDGE_CURRENT_APP and RAM_SIGNING_BRIDGE_CANDIDATE_APP.")
        }

        let currentURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        let candidateURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
        let assetURL = URL(
            string: "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/download/v1.1.2/test"
        )!
        let asset = SoftwareUpdateAsset(
            name: "test",
            downloadURL: assetURL,
            byteCount: 1,
            digest: "sha256:\(String(repeating: "a", count: 64))"
        )
        let release = SoftwareUpdateRelease(
            version: AppVersion("1.1.2")!,
            title: "Signing bridge test",
            notes: "",
            pageURL: URL(
                string: "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/tag/v1.1.2"
            )!,
            publishedAt: nil,
            archive: asset,
            checksum: asset,
            signature: asset
        )
        let service = GitHubSoftwareUpdateService()

        XCTAssertNoThrow(try service.validateApplication(
            candidateURL,
            release: release,
            currentApplicationURL: currentURL
        ))

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAMac-Wrong-Signer-Test-\(UUID().uuidString)", isDirectory: true)
        let wrongSignerURL = workspace.appendingPathComponent(
            "Roblox Account Manager.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.copyItem(at: candidateURL, to: wrongSignerURL)
        XCTAssertEqual(Self.run("/usr/bin/codesign", [
            "--force", "--deep", "--sign", "-", wrongSignerURL.path
        ]), 0)
        XCTAssertThrowsError(try service.validateApplication(
            wrongSignerURL,
            release: release,
            currentApplicationURL: currentURL
        )) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .wrongSigningIdentity)
        }
    }

    private func makeService() -> GitHubSoftwareUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SoftwareUpdateURLProtocol.self]
        return GitHubSoftwareUpdateService(session: URLSession(configuration: configuration))
    }

    private static func releaseJSON(
        version: String,
        prerelease: Bool = false,
        draft: Bool = false,
        publishedAt: String = "2026-08-13T12:00:00Z",
        pageURL: String? = nil,
        includeSignature: Bool = true
    ) -> String {
        let archiveName = "Roblox-Account-Manager-for-Mac-\(version).zip"
        let digest = String(repeating: "a", count: 64)
        let releasePageURL = pageURL
            ?? "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/tag/v\(version)"
        let signatureAsset = includeSignature ? """
            ,
            {
              "name": "\(archiveName).sig",
              "browser_download_url": "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/download/v\(version)/\(archiveName).sig",
              "size": 72,
              "digest": "sha256:\(digest)",
              "state": "uploaded"
            }
        """ : ""
        return """
        {
          "tag_name": "v\(version)",
          "name": "Roblox Account Manager for Mac \(version)",
          "body": "Update notes",
          "html_url": "\(releasePageURL)",
          "published_at": "\(publishedAt)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [
            {
              "name": "\(archiveName)",
              "browser_download_url": "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/download/v\(version)/\(archiveName)",
              "size": 100,
              "digest": "sha256:\(digest)",
              "state": "uploaded"
            },
            {
              "name": "\(archiveName).sha256",
              "browser_download_url": "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/download/v\(version)/\(archiveName).sha256",
              "size": 90,
              "digest": "sha256:\(digest)",
              "state": "uploaded"
            }
            \(signatureAsset)
          ]
        }
        """
    }

    private static func response(_ request: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static func bundleVersion(at applicationURL: URL) -> String? {
        let plistURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: plistURL)?["CFBundleShortVersionString"] as? String)
    }

    private static func designatedRequirement(at path: String) throws -> SecRequirement {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &code
        ) == errSecSuccess,
        let code else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(
            code,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
        let requirement else {
            throw SoftwareUpdateError.wrongSigningIdentity
        }
        return requirement
    }

    private static func makeInstallerFixture() throws -> (
        workspaceURL: URL,
        currentURL: URL,
        prepared: PreparedSoftwareUpdate
    ) {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAMac-Installer-Test-\(UUID().uuidString)", isDirectory: true)
        let currentURL = workspaceURL.appendingPathComponent(
            "Roblox Account Manager.app",
            isDirectory: true
        )
        let preparedURL = workspaceURL.appendingPathComponent("Prepared.app", isDirectory: true)
        try FileManager.default.createDirectory(at: currentURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preparedURL, withIntermediateDirectories: true)
        try Data("current".utf8).write(to: currentURL.appendingPathComponent("marker"))
        try Data("candidate".utf8).write(to: preparedURL.appendingPathComponent("marker"))
        let assetURL = URL(
            string: "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/download/v1.1.2/test"
        )!
        let asset = SoftwareUpdateAsset(
            name: "test",
            downloadURL: assetURL,
            byteCount: 1,
            digest: "sha256:\(String(repeating: "a", count: 64))"
        )
        let release = SoftwareUpdateRelease(
            version: AppVersion("1.1.2")!,
            title: "Installer test",
            notes: "",
            pageURL: assetURL,
            publishedAt: nil,
            archive: asset,
            checksum: asset,
            signature: asset
        )
        return (
            workspaceURL,
            currentURL,
            PreparedSoftwareUpdate(
                release: release,
                applicationURL: preparedURL,
                workspaceURL: workspaceURL
            )
        )
    }


    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

private final class SoftwareUpdateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

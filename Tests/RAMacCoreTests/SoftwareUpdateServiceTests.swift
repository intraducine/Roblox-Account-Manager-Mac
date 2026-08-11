import Foundation
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
            XCTAssertEqual(request.url?.path, "/repos/intraducine/Roblox-Account-Manager-Mac/releases/latest")
            return Self.response(request, Self.releaseJSON(version: "1.0.3"))
        }

        let result = try await makeService().check(currentVersion: "1.0.2")

        guard case .available(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(release.version, AppVersion("1.0.3"))
        XCTAssertEqual(release.archive.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip")
        XCTAssertEqual(release.checksum.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip.sha256")
    }

    func testUpdateCheckDoesNotInstallAnOlderRelease() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            Self.response(request, Self.releaseJSON(version: "1.0.2"))
        }

        let result = try await makeService().check(currentVersion: "1.0.3")

        XCTAssertEqual(result, .upToDate(currentVersion: "1.0.3"))
    }

    func testUpdateCheckRejectsPrerelease() async throws {
        SoftwareUpdateURLProtocol.handler = { request in
            Self.response(request, Self.releaseJSON(version: "1.0.4", prerelease: true))
        }

        do {
            _ = try await makeService().check(currentVersion: "1.0.3")
            XCTFail("Expected prerelease rejection")
        } catch let error as SoftwareUpdateError {
            XCTAssertEqual(error, .invalidRelease)
        }
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
            return XCTFail("Expected the published version 1.0.3 release")
        }
        XCTAssertEqual(release.version, AppVersion("1.0.3"))

        let prepared = try await service.downloadAndPrepare(
            release,
            currentApplicationURL: currentURL
        )
        defer { service.discard(prepared) }
        let installer = SoftwareUpdateInstaller(service: service)
        let backupURL = try installer.install(prepared, replacing: currentURL)

        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.0.3")
        XCTAssertEqual(Self.bundleVersion(at: backupURL), "1.0.2")
        try installer.restorePreviousVersion(from: backupURL, to: currentURL)
        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.0.2")
    }

    private func makeService() -> GitHubSoftwareUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SoftwareUpdateURLProtocol.self]
        return GitHubSoftwareUpdateService(session: URLSession(configuration: configuration))
    }

    private static func releaseJSON(version: String, prerelease: Bool = false) -> String {
        let archiveName = "Roblox-Account-Manager-for-Mac-\(version).zip"
        let digest = String(repeating: "a", count: 64)
        return """
        {
          "tag_name": "v\(version)",
          "name": "Roblox Account Manager for Mac \(version)",
          "body": "Update notes",
          "html_url": "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/tag/v\(version)",
          "draft": false,
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

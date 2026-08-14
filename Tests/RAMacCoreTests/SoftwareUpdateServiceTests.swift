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
        XCTAssertEqual(release.publishedAt, ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z"))
        XCTAssertEqual(release.archive.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip")
        XCTAssertEqual(release.checksum.name, "Roblox-Account-Manager-for-Mac-1.0.3.zip.sha256")
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
            return XCTFail("Expected the published version 1.0.4 release")
        }
        XCTAssertEqual(release.version, AppVersion("1.0.4"))

        let prepared = try await service.downloadAndPrepare(
            release,
            currentApplicationURL: currentURL
        )
        defer { service.discard(prepared) }
        let installer = SoftwareUpdateInstaller(service: service)
        let backupURL = try installer.install(prepared, replacing: currentURL)

        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.0.4")
        XCTAssertEqual(Self.bundleVersion(at: backupURL), "1.0.2")
        try installer.restorePreviousVersion(from: backupURL, to: currentURL)
        XCTAssertEqual(Self.bundleVersion(at: currentURL), "1.0.2")
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
        pageURL: String? = nil
    ) -> String {
        let archiveName = "Roblox-Account-Manager-for-Mac-\(version).zip"
        let digest = String(repeating: "a", count: 64)
        let releasePageURL = pageURL
            ?? "https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/tag/v\(version)"
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

import Foundation
import XCTest
@testable import RAMacCore

final class RobloxExperienceMetadataClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExperienceMetadataURLProtocol.handler = nil
    }

    func testLoadsPublicGameNameAndIconWithoutAccountCookie() async throws {
        ExperienceMetadataURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "Roblox Account Manager for Mac/1.1.2"
            )
            switch request.url?.host {
            case "apis.roblox.com":
                XCTAssertEqual(request.url?.path, "/universes/v1/places/1818/universe")
                return Self.response(request, #"{"universeId":13058}"#)
            case "games.roblox.com":
                XCTAssertEqual(Self.queryValue("universeIds", request), "13058")
                return Self.response(request, #"{"data":[{"id":13058,"name":"Classic: Crossroads"}]}"#)
            case "thumbnails.roblox.com":
                XCTAssertEqual(Self.queryValue("universeIds", request), "13058")
                XCTAssertEqual(Self.queryValue("size", request), "150x150")
                return Self.response(
                    request,
                    #"{"data":[{"targetId":13058,"state":"Completed","imageUrl":"https://tr.rbxcdn.com/crossroads.png"}]}"#
                )
            default:
                return Self.response(request, "{}", status: 404)
            }
        }

        let metadata = try await makeClient().metadata(placeID: 1818)

        XCTAssertEqual(metadata.placeID, 1818)
        XCTAssertEqual(metadata.universeID, 13058)
        XCTAssertEqual(metadata.name, "Classic: Crossroads")
        XCTAssertEqual(metadata.thumbnailURLString, "https://tr.rbxcdn.com/crossroads.png")
    }

    func testPendingIconStillReturnsTheGameName() async throws {
        ExperienceMetadataURLProtocol.handler = { request in
            switch request.url?.host {
            case "apis.roblox.com":
                return Self.response(request, #"{"universeId":99}"#)
            case "games.roblox.com":
                return Self.response(request, #"{"data":[{"id":99,"name":"Example Game"}]}"#)
            case "thumbnails.roblox.com":
                return Self.response(request, #"{"data":[{"targetId":99,"state":"Pending","imageUrl":null}]}"#)
            default:
                return Self.response(request, "{}", status: 404)
            }
        }

        let metadata = try await makeClient().metadata(placeID: 55)

        XCTAssertEqual(metadata.name, "Example Game")
        XCTAssertNil(metadata.thumbnailURLString)
    }

    func testExperienceRecordDisplaysOnlyTrustedRobloxIconURLs() {
        XCTAssertNotNil(ExperienceRecord(
            placeID: 1,
            thumbnailURLString: "https://tr.rbxcdn.com/icon.png"
        ).thumbnailURL)
        XCTAssertNil(ExperienceRecord(
            placeID: 1,
            thumbnailURLString: "https://example.com/tracker.png"
        ).thumbnailURL)
        XCTAssertNil(ExperienceRecord(
            placeID: 1,
            thumbnailURLString: "http://tr.rbxcdn.com/icon.png"
        ).thumbnailURL)
    }

    private func makeClient() -> RobloxExperienceMetadataClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExperienceMetadataURLProtocol.self]
        return RobloxExperienceMetadataClient(
            session: URLSession(configuration: configuration),
            userAgent: "Roblox Account Manager for Mac/1.1.2"
        )
    }

    private static func queryValue(_ name: String, _ request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static func response(
        _ request: URLRequest,
        _ body: String,
        status: Int = 200
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

private final class ExperienceMetadataURLProtocol: URLProtocol {
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

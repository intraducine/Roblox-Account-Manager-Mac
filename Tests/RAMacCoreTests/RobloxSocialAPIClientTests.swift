import Foundation
import XCTest
@testable import RAMacCore

final class RobloxSocialAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SocialMockURLProtocol.handler = nil
        SocialMockURLProtocol.requestCount = 0
    }

    func testCookieIsUsedOnlyForTheAuthenticatedRequest() async throws {
        var call = 0
        let client = makeClient { request in
            call += 1
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "Roblox Account Manager for Mac/1.1.2"
            )
            if call == 1 {
                XCTAssertEqual(request.url?.path, "/v1/users/42/friends/online")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), ".ROBLOSECURITY=secret")
                return Self.response(request, status: 200, body: #"{"data":[]}"#)
            }
            XCTAssertEqual(request.url?.path, "/v1/presence/users")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return Self.response(request, status: 200, body: #"{"userPresences":[]}"#)
        }

        _ = try await client.onlineFriends(of: 42, session: "secret")
        _ = try await client.presences(for: [7], session: nil)
        XCTAssertEqual(call, 2)
    }

    func testOnlineFriendsDecodeTheCurrentNestedPresenceShape() async throws {
        let jobID = "11111111-2222-3333-4444-555555555555"
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/users/42/friends/online")
            return Self.response(
                request,
                status: 200,
                body: #"{"data":[{"id":7,"name":"friend","displayName":"Friend","userPresence":{"UserPresenceType":"InGame","UserLocationType":"Game","lastLocation":"Test","placeId":1818,"rootPlaceId":1818,"gameInstanceId":"\#(jobID)","universeId":13058}}]}"#
            )
        }

        let friends = try await client.onlineFriends(of: 42, session: "secret")

        XCTAssertEqual(friends.count, 1)
        XCTAssertEqual(friends[0].userPresenceType, RobloxPresenceType.inExperience.rawValue)
        XCTAssertEqual(friends[0].placeId, 1818)
        XCTAssertEqual(friends[0].gameId, jobID)
        XCTAssertEqual(friends[0].lastLocation, "Test")
    }

    func testStatusCodesHaveSeparateErrors() async {
        for (status, expected) in [
            (401, RobloxSocialAPIError.signedOut),
            (403, RobloxSocialAPIError.forbidden),
            (404, RobloxSocialAPIError.notFound)
        ] {
            let client = makeClient { request in Self.response(request, status: status) }
            do {
                _ = try await client.friends(of: 42)
                XCTFail("Expected status \(status) to fail")
            } catch let error as RobloxSocialAPIError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingNamesCanLoadFromPublicUserIDs() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.host, "users.roblox.com")
            XCTAssertEqual(request.url?.path, "/v1/users")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return Self.response(
                request,
                status: 200,
                body: #"{"data":[{"id":7,"name":"resolved","displayName":"Resolved"}]}"#
            )
        }

        let users = try await client.users(for: [7])
        XCTAssertEqual(users, [.init(id: 7, name: "resolved", displayName: "Resolved")])
    }

    func testRateLimitRetriesSafeReadThenReportsRetryAfter() async {
        let client = makeClient { request in
            Self.response(request, status: 429, headers: ["Retry-After": "0"])
        }

        do {
            _ = try await client.friends(of: 42)
            XCTFail("Expected a rate-limit error")
        } catch let error as RobloxSocialAPIError {
            XCTAssertEqual(error, .rateLimited(0))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(SocialMockURLProtocol.requestCount, 3)
    }

    func testOnlineFriendRateLimitDoesNotRetryInABurst() async {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/users/42/friends/online")
            return Self.response(request, status: 429, headers: ["Retry-After": "45"])
        }

        do {
            _ = try await client.onlineFriends(of: 42, session: "secret")
            XCTFail("Expected a rate-limit error")
        } catch let error as RobloxSocialAPIError {
            XCTAssertEqual(error, .rateLimited(45))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(SocialMockURLProtocol.requestCount, 1)
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> RobloxSocialAPIClient {
        SocialMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.protocolClasses = [SocialMockURLProtocol.self]
        return RobloxSocialAPIClient(
            session: URLSession(configuration: configuration),
            userAgent: "Roblox Account Manager for Mac/1.1.2"
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        headers: [String: String] = [:],
        body: String = ""
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!,
            Data(body.utf8)
        )
    }
}

private final class SocialMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("Missing URL handler")
            return
        }
        do {
            Self.requestCount += 1
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

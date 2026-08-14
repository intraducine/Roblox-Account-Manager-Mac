import Foundation
import XCTest
@testable import RAMacCore

final class RobloxAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
        MockURLProtocol.requests = []
    }

    func testNormalizesCookieHeaderAndPlainValue() {
        XCTAssertEqual(
            RobloxAPIClient.normalizedCookie(from: "  .ROBLOSECURITY=secret-value; Path=/;  "),
            "secret-value"
        )
        XCTAssertEqual(RobloxAPIClient.normalizedCookie(from: " secret-value; "), "secret-value")
    }

    func testValidatesAuthenticatedUser() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), ".ROBLOSECURITY=secret")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "Roblox Account Manager for Mac/1.1.2"
            )
            return Self.response(
                request: request,
                status: 200,
                body: #"{"id":42,"name":"builder","displayName":"Builder"}"#
            )
        }
        let user = try await client.authenticatedUser(cookie: "secret")
        XCTAssertEqual(user, RobloxUser(id: 42, name: "builder", displayName: "Builder"))
    }

    func testAuthenticationTicketCompletesCSRFChallenge() async throws {
        var call = 0
        let client = makeClient { request in
            call += 1
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://www.roblox.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.roblox.com/")
            XCTAssertEqual(Self.bodyData(from: request), Data("{}".utf8))
            if call == 1 {
                return Self.response(
                    request: request,
                    status: 403,
                    headers: ["x-csrf-token": "csrf"]
                )
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-csrf-token"), "csrf")
            return Self.response(
                request: request,
                status: 200,
                headers: ["rbx-authentication-ticket": "launch-ticket"]
            )
        }
        let ticket = try await client.authenticationTicket(cookie: "secret")
        XCTAssertEqual(ticket, "launch-ticket")
        XCTAssertEqual(call, 2)
    }

    func testResolvesCurrentPrivateServerShareLinkForTheAccount() async throws {
        var call = 0
        let client = makeClient { request in
            call += 1
            XCTAssertEqual(request.url?.absoluteString, "https://apis.roblox.com/sharelinks/v1/resolve-link")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), ".ROBLOSECURITY=secret")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(object, ["linkId": "share-code", "linkType": "Server"])
            if call == 1 {
                return Self.response(
                    request: request,
                    status: 403,
                    headers: ["x-csrf-token": "csrf"]
                )
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-csrf-token"), "csrf")
            return Self.response(
                request: request,
                status: 200,
                body: #"{"privateServerInviteData":{"status":"Valid","placeId":17625359962,"linkCode":"resolved-private-code","ownerUserId":1,"privateServerId":2,"universeId":3}}"#
            )
        }

        let resolution = try await client.privateShareLinkResolution(
            shareCode: "share-code",
            cookie: "secret"
        )

        XCTAssertEqual(
            resolution,
            RobloxPrivateShareLinkResolution(placeID: 17_625_359_962, linkCode: "resolved-private-code")
        )
        XCTAssertEqual(call, 2)
    }

    func testInvalidPrivateServerShareLinkHasClearError() async {
        let client = makeClient { request in
            Self.response(
                request: request,
                status: 200,
                body: #"{"privateServerInviteData":{"status":"Expired","placeId":null,"linkCode":null}}"#
            )
        }

        do {
            _ = try await client.privateShareLinkResolution(shareCode: "expired", cookie: "secret")
            XCTFail("Expected unavailable private server")
        } catch let error as RobloxAPIError {
            XCTAssertEqual(error, .privateServerUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadsAvatarURL() async {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.host, "thumbnails.roblox.com")
            return Self.response(
                request: request,
                status: 200,
                body: #"{"data":[{"state":"Completed","imageUrl":"https://tr.rbxcdn.com/avatar.png"}]}"#
            )
        }
        let avatar = await client.avatarURL(userID: 42)
        XCTAssertEqual(avatar?.absoluteString, "https://tr.rbxcdn.com/avatar.png")
    }

    func testRejectsAvatarOutsideRobloxCDN() async {
        let client = makeClient { request in
            Self.response(
                request: request,
                status: 200,
                body: #"{"data":[{"state":"Completed","imageUrl":"https://127.0.0.1/avatar.png"}]}"#
            )
        }
        let avatar = await client.avatarURL(userID: 42)
        XCTAssertNil(avatar)
    }

    func testRejectsUsernameResponseForAnotherIdentity() async {
        let client = makeClient { request in
            Self.response(
                request: request,
                status: 200,
                body: #"{"data":[{"requestedUsername":"someone-else","id":156,"name":"someone-else","displayName":"Someone"}]}"#
            )
        }

        do {
            _ = try await client.user(named: "builderman")
            XCTFail("Expected a mismatched identity to be rejected")
        } catch let error as RobloxAPIError {
            XCTAssertEqual(error, .userNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsPresenceResponseForAnotherUser() async {
        let client = makeClient { request in
            Self.response(
                request: request,
                status: 200,
                body: #"{"userPresences":[{"userPresenceType":2,"placeId":1818,"gameId":"11111111-2222-3333-4444-555555555555","userId":999}]}"#
            )
        }

        do {
            _ = try await client.presence(userID: 156)
            XCTFail("Expected a mismatched presence to be rejected")
        } catch let error as RobloxAPIError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidSessionHasDirectError() async {
        let client = makeClient { request in
            Self.response(request: request, status: 401, body: #"{"errors":[]}"#)
        }
        do {
            _ = try await client.authenticatedUser(cookie: "expired")
            XCTFail("Expected invalid session")
        } catch let error as RobloxAPIError {
            XCTAssertEqual(error, .invalidSession)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadsPublicServersWithoutSendingAccountCookie() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.host, "games.roblox.com")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "limit" })?.value, "100")
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "excludeFullGames" })?.value, "false")
            return Self.response(
                request: request,
                status: 200,
                body: #"{"previousPageCursor":null,"nextPageCursor":"next","data":[{"id":"11111111-2222-3333-4444-555555555555","maxPlayers":8,"playing":3,"fps":59.9,"ping":92}]}"#
            )
        }

        let page = try await client.publicServers(placeID: 1818, cursor: nil)
        XCTAssertEqual(page.nextPageCursor, "next")
        XCTAssertEqual(page.data.first?.openSpaces, 5)
    }

    func testLooksUpPublicPlayerPresenceWithoutSendingAccountCookie() async throws {
        var call = 0
        let client = makeClient { request in
            call += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            if call == 1 {
                XCTAssertEqual(request.url?.host, "users.roblox.com")
                return Self.response(
                    request: request,
                    status: 200,
                    body: #"{"data":[{"requestedUsername":"builderman","id":156,"name":"builderman","displayName":"builderman"}]}"#
                )
            }
            XCTAssertEqual(request.url?.host, "presence.roblox.com")
            return Self.response(
                request: request,
                status: 200,
                body: #"{"userPresences":[{"userPresenceType":2,"lastLocation":"Test Place","placeId":1818,"rootPlaceId":1818,"gameId":"11111111-2222-3333-4444-555555555555","universeId":13058,"userId":156}]}"#
            )
        }

        let user = try await client.user(named: "@builderman")
        let presence = try await client.presence(userID: user.id)
        XCTAssertEqual(user.id, 156)
        XCTAssertEqual(presence.placeId, 1818)
        XCTAssertEqual(presence.gameId, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(call, 2)
    }

    func testPublicServerRateLimitHasDirectError() async {
        let client = makeClient { request in
            Self.response(
                request: request,
                status: 429,
                headers: ["x-ratelimit-reset": "12"]
            )
        }

        do {
            _ = try await client.publicServers(placeID: 1818, cursor: nil)
            XCTFail("Expected rate limit")
        } catch let error as RobloxAPIError {
            XCTAssertEqual(error, .rateLimited(12))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPublicServerBudgetStopsTheNextRequestBeforeRobloxReceivesIt() async throws {
        var calls = 0
        let client = makeClient { request in
            calls += 1
            return Self.response(
                request: request,
                status: 200,
                headers: [
                    "x-ratelimit-limit": "3, 3;w=60",
                    "x-ratelimit-remaining": "0",
                    "x-ratelimit-reset": "12"
                ],
                body: #"{"previousPageCursor":null,"nextPageCursor":"next","data":[]}"#
            )
        }

        _ = try await client.publicServers(placeID: 1818, cursor: nil)
        do {
            _ = try await client.publicServers(placeID: 1818, cursor: "next")
            XCTFail("Expected the local request budget to pause")
        } catch let error as RobloxAPIError {
            guard case .requestBudgetPaused(let retryAfter) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertNotNil(retryAfter)
            XCTAssertGreaterThanOrEqual(retryAfter ?? 0, 12)
        }
        XCTAssertEqual(calls, 1)
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> RobloxAPIClient {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return RobloxAPIClient(session: URLSession(configuration: configuration))
    }

    private static func response(
        request: URLRequest,
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

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var body = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("Missing URL handler")
            return
        }
        do {
            Self.requests.append(request)
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

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

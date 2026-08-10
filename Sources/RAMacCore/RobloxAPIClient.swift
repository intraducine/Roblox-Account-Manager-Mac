import Foundation

public enum RobloxAPIError: LocalizedError, Equatable {
    case invalidSession
    case invalidResponse
    case csrfUnavailable
    case authenticationTicketUnavailable
    case privateServerUnavailable
    case server(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "This Roblox session is not valid. Sign in again."
        case .invalidResponse:
            return "Roblox returned a response that this app could not read."
        case .csrfUnavailable:
            return "Roblox did not return the required request token. Sign in again."
        case .authenticationTicketUnavailable:
            return "Roblox did not issue a launch ticket. Try again in a moment."
        case .privateServerUnavailable:
            return "The private server link could not be resolved for this account."
        case .server(let status, let message):
            return "Roblox returned \(status): \(message)"
        }
    }
}

public protocol RobloxAPIProviding: Sendable {
    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser
    func avatarURL(userID: Int64) async -> URL?
    func authenticationTicket(cookie rawCookie: String) async throws -> String
    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String
}

public struct RobloxAPIClient: Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    public static func normalizedCookie(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = trimmed.range(of: ".ROBLOSECURITY=") {
            let valueStart = marker.upperBound
            let suffix = trimmed[valueStart...]
            return String(suffix.split(separator: ";", maxSplits: 1).first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ";"))
    }

    public func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        let cookie = Self.normalizedCookie(from: rawCookie)
        guard !cookie.isEmpty else { throw RobloxAPIError.invalidSession }
        var request = URLRequest(url: URL(string: "https://users.roblox.com/v1/users/authenticated")!)
        request.httpMethod = "GET"
        applyHeaders(cookie: cookie, to: &request)
        let (data, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw RobloxAPIError.invalidSession }
            throw RobloxAPIError.server(http.statusCode, serverMessage(from: data))
        }
        do {
            return try decoder.decode(RobloxUser.self, from: data)
        } catch {
            throw RobloxAPIError.invalidResponse
        }
    }

    public func avatarURL(userID: Int64) async -> URL? {
        var components = URLComponents(string: "https://thumbnails.roblox.com/v1/users/avatar-headshot")!
        components.queryItems = [
            URLQueryItem(name: "userIds", value: String(userID)),
            URLQueryItem(name: "size", value: "150x150"),
            URLQueryItem(name: "format", value: "Png"),
            URLQueryItem(name: "isCircular", value: "false")
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? decoder.decode(RobloxThumbnailResponse.self, from: data),
              let image = payload.data.first?.imageUrl else { return nil }
        return URL(string: image)
    }

    public func authenticationTicket(cookie rawCookie: String) async throws -> String {
        let cookie = Self.normalizedCookie(from: rawCookie)
        guard !cookie.isEmpty else { throw RobloxAPIError.invalidSession }
        let endpoint = URL(string: "https://auth.roblox.com/v1/authentication-ticket/")!
        var challenge = URLRequest(url: endpoint)
        challenge.httpMethod = "POST"
        challenge.httpBody = Data()
        applyHeaders(cookie: cookie, to: &challenge)

        let (challengeData, challengeResponse) = try await session.data(for: challenge)
        let first = try httpResponse(challengeResponse)
        if let ticket = first.value(forHTTPHeaderField: "rbx-authentication-ticket"), !ticket.isEmpty {
            return ticket
        }
        guard let csrf = first.value(forHTTPHeaderField: "x-csrf-token"), !csrf.isEmpty else {
            if first.statusCode == 401 { throw RobloxAPIError.invalidSession }
            if first.statusCode != 403 {
                throw RobloxAPIError.server(first.statusCode, serverMessage(from: challengeData))
            }
            throw RobloxAPIError.csrfUnavailable
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        applyHeaders(cookie: cookie, to: &request)
        let (data, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw RobloxAPIError.invalidSession }
            throw RobloxAPIError.server(http.statusCode, serverMessage(from: data))
        }
        guard let ticket = http.value(forHTTPHeaderField: "rbx-authentication-ticket"), !ticket.isEmpty else {
            throw RobloxAPIError.authenticationTicketUnavailable
        }
        return ticket
    }

    public func privateServerAccessCode(
        placeID: Int64,
        linkCode: String,
        cookie rawCookie: String
    ) async throws -> String {
        var components = URLComponents(string: "https://www.roblox.com/games/\(placeID)")!
        components.queryItems = [URLQueryItem(name: "privateServerLinkCode", value: linkCode)]
        var request = URLRequest(url: components.url!)
        applyHeaders(cookie: Self.normalizedCookie(from: rawCookie), to: &request)
        let (data, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        guard (200...299).contains(http.statusCode), let html = String(data: data, encoding: .utf8) else {
            throw RobloxAPIError.privateServerUnavailable
        }
        let pattern = #"Roblox\.GameLauncher\.joinPrivateGame\(\d+\s*,\s*'([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            throw RobloxAPIError.privateServerUnavailable
        }
        return String(html[range])
    }

    private func applyHeaders(cookie: String, to request: inout URLRequest) {
        request.setValue(".ROBLOSECURITY=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.roblox.com/", forHTTPHeaderField: "Referer")
        request.setValue("Roblox Account Manager for Mac/0.3", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw RobloxAPIError.invalidResponse }
        return response
    }

    private func serverMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = object["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String
        else { return "Request failed" }
        return message
    }
}

extension RobloxAPIClient: RobloxAPIProviding {}

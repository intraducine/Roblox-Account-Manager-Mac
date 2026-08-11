import Foundation

public enum RobloxAPIError: LocalizedError, Equatable {
    case invalidSession
    case invalidResponse
    case csrfUnavailable
    case authenticationTicketUnavailable
    case privateServerUnavailable
    case rateLimited(Int?)
    case requestBudgetPaused(Int?)
    case userNotFound
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
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "Roblox is limiting server requests. Try again in \(retryAfter) seconds."
            }
            return "Roblox is limiting server requests. Try again in a minute."
        case .requestBudgetPaused(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                let unit = retryAfter == 1 ? "second" : "seconds"
                return "Server checking is paused to stay within Roblox's request limit. Try again in \(retryAfter) \(unit)."
            }
            return "Server checking is paused to stay within Roblox's request limit. Try again in a minute."
        case .userNotFound:
            return "Roblox could not find that username."
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
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage
    func user(named username: String) async throws -> RobloxUserSearchResult
    func presence(userID: Int64) async throws -> RobloxUserPresence
}

public extension RobloxAPIProviding {
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage {
        throw RobloxAPIError.invalidResponse
    }

    func user(named username: String) async throws -> RobloxUserSearchResult {
        throw RobloxAPIError.userNotFound
    }

    func presence(userID: Int64) async throws -> RobloxUserPresence {
        throw RobloxAPIError.invalidResponse
    }
}

public struct RobloxAPIClient: Sendable {
    private let session: URLSession
    private let publicServerLimiter: PublicServerRequestLimiter
    private let decoder = JSONDecoder()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            publicServerLimiter = PublicServerRequestLimiter()
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
            publicServerLimiter = .shared
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

    public func publicServers(placeID: Int64, cursor: String? = nil) async throws -> RobloxPublicServerPage {
        guard placeID > 0 else { throw RobloxLaunchError.invalidPlaceID }
        try await publicServerLimiter.acquirePermit()
        var components = URLComponents(string: "https://games.roblox.com/v1/games/\(placeID)/servers/Public")!
        var queryItems = [
            URLQueryItem(name: "sortOrder", value: "Asc"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "excludeFullGames", value: "false")
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        applyPublicHeaders(to: &request)
        let data: Data
        let http: HTTPURLResponse
        do {
            let response = try await session.data(for: request)
            data = response.0
            http = try httpResponse(response.1)
            await publicServerLimiter.observe(http)
        } catch {
            await publicServerLimiter.requestFailedBeforeResponse()
            throw error
        }
        try checkDiscoveryStatus(http, data: data)
        do {
            return try decoder.decode(RobloxPublicServerPage.self, from: data)
        } catch {
            throw RobloxAPIError.invalidResponse
        }
    }

    public func user(named username: String) async throws -> RobloxUserSearchResult {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !clean.isEmpty else { throw RobloxAPIError.userNotFound }
        var request = URLRequest(url: URL(string: "https://users.roblox.com/v1/usernames/users")!)
        request.httpMethod = "POST"
        applyPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "usernames": [clean],
            "excludeBannedUsers": true
        ])
        let (data, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        try checkDiscoveryStatus(http, data: data)
        do {
            guard let user = try decoder.decode(RobloxUserSearchResponse.self, from: data).data.first else {
                throw RobloxAPIError.userNotFound
            }
            return user
        } catch let error as RobloxAPIError {
            throw error
        } catch {
            throw RobloxAPIError.invalidResponse
        }
    }

    public func presence(userID: Int64) async throws -> RobloxUserPresence {
        var request = URLRequest(url: URL(string: "https://presence.roblox.com/v1/presence/users")!)
        request.httpMethod = "POST"
        applyPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userIds": [userID]])
        let (data, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        try checkDiscoveryStatus(http, data: data)
        do {
            guard let presence = try decoder.decode(RobloxPresenceResponse.self, from: data).userPresences.first else {
                throw RobloxAPIError.invalidResponse
            }
            return presence
        } catch let error as RobloxAPIError {
            throw error
        } catch {
            throw RobloxAPIError.invalidResponse
        }
    }

    public func authenticationTicket(cookie rawCookie: String) async throws -> String {
        let cookie = Self.normalizedCookie(from: rawCookie)
        guard !cookie.isEmpty else { throw RobloxAPIError.invalidSession }
        let endpoint = URL(string: "https://auth.roblox.com/v1/authentication-ticket/")!
        var challenge = URLRequest(url: endpoint)
        challenge.httpMethod = "POST"
        applyJSONBody(to: &challenge)
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
        applyJSONBody(to: &request)
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
        request.setValue("https://www.roblox.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.roblox.com/", forHTTPHeaderField: "Referer")
        request.setValue("Roblox Account Manager for Mac/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func applyPublicHeaders(to request: inout URLRequest) {
        request.setValue("Roblox Account Manager for Mac/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func applyJSONBody(to request: inout URLRequest) {
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw RobloxAPIError.invalidResponse }
        return response
    }

    private func checkDiscoveryStatus(_ response: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 429 {
                let retry = response.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
                    ?? response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Int.init)
                throw RobloxAPIError.rateLimited(retry)
            }
            throw RobloxAPIError.server(response.statusCode, serverMessage(from: data))
        }
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

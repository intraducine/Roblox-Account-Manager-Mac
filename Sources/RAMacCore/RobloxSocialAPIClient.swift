import Foundation

public struct RobloxSocialUser: Codable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let displayName: String

    public init(id: Int64, name: String, displayName: String) {
        self.id = id
        self.name = name
        self.displayName = displayName
    }
}

public struct RobloxVisibleFriend: Decodable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let displayName: String
    public let userPresenceType: Int?
    public let placeId: Int64?
    public let rootPlaceId: Int64?
    public let gameId: String?
    public let universeId: Int64?
    public let lastLocation: String?

    public init(
        id: Int64,
        name: String,
        displayName: String,
        userPresenceType: Int? = nil,
        placeId: Int64? = nil,
        rootPlaceId: Int64? = nil,
        gameId: String? = nil,
        universeId: Int64? = nil,
        lastLocation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.userPresenceType = userPresenceType
        self.placeId = placeId
        self.rootPlaceId = rootPlaceId
        self.gameId = gameId
        self.universeId = universeId
        self.lastLocation = lastLocation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case userPresence
        case userPresenceType
        case placeId
        case rootPlaceId
        case gameId
        case universeId
        case lastLocation
    }

    private enum PresenceKeys: String, CodingKey {
        case userPresenceType = "UserPresenceType"
        case lowerUserPresenceType = "userPresenceType"
        case lastLocation
        case placeId
        case rootPlaceId
        case gameInstanceId
        case gameId
        case universeId
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? name

        if let presence = try? values.nestedContainer(keyedBy: PresenceKeys.self, forKey: .userPresence) {
            let stringType = (try? presence.decodeIfPresent(String.self, forKey: .userPresenceType))
                ?? (try? presence.decodeIfPresent(String.self, forKey: .lowerUserPresenceType))
            let integerType = (try? presence.decodeIfPresent(Int.self, forKey: .userPresenceType))
                ?? (try? presence.decodeIfPresent(Int.self, forKey: .lowerUserPresenceType))
            placeId = try presence.decodeIfPresent(Int64.self, forKey: .placeId)
            rootPlaceId = try presence.decodeIfPresent(Int64.self, forKey: .rootPlaceId)
            gameId = try presence.decodeIfPresent(String.self, forKey: .gameInstanceId)
                ?? presence.decodeIfPresent(String.self, forKey: .gameId)
            universeId = try presence.decodeIfPresent(Int64.self, forKey: .universeId)
            lastLocation = try presence.decodeIfPresent(String.self, forKey: .lastLocation)
            userPresenceType = integerType
                ?? Self.presenceType(from: stringType, hasGameTarget: placeId != nil && gameId != nil)
        } else {
            userPresenceType = try values.decodeIfPresent(Int.self, forKey: .userPresenceType)
            placeId = try values.decodeIfPresent(Int64.self, forKey: .placeId)
            rootPlaceId = try values.decodeIfPresent(Int64.self, forKey: .rootPlaceId)
            gameId = try values.decodeIfPresent(String.self, forKey: .gameId)
            universeId = try values.decodeIfPresent(Int64.self, forKey: .universeId)
            lastLocation = try values.decodeIfPresent(String.self, forKey: .lastLocation)
        }
    }

    private static func presenceType(from value: String?, hasGameTarget: Bool) -> Int {
        let normalized = value?.lowercased() ?? ""
        if normalized.contains("studio") { return RobloxPresenceType.inStudio.rawValue }
        if normalized.contains("game") || normalized.contains("experience") {
            return RobloxPresenceType.inExperience.rawValue
        }
        if normalized.contains("online") || normalized.contains("website") {
            return RobloxPresenceType.online.rawValue
        }
        if normalized.contains("invisible") { return RobloxPresenceType.invisible.rawValue }
        if hasGameTarget { return RobloxPresenceType.inExperience.rawValue }
        return RobloxPresenceType.offline.rawValue
    }
}

public struct RobloxSocialPresence: Codable, Equatable, Sendable {
    public let userPresenceType: Int
    public let lastLocation: String?
    public let placeId: Int64?
    public let rootPlaceId: Int64?
    public let gameId: String?
    public let universeId: Int64?
    public let userId: Int64

    public init(
        userPresenceType: Int,
        lastLocation: String? = nil,
        placeId: Int64? = nil,
        rootPlaceId: Int64? = nil,
        gameId: String? = nil,
        universeId: Int64? = nil,
        userId: Int64
    ) {
        self.userPresenceType = userPresenceType
        self.lastLocation = lastLocation
        self.placeId = placeId
        self.rootPlaceId = rootPlaceId
        self.gameId = gameId
        self.universeId = universeId
        self.userId = userId
    }
}

public enum RobloxSocialAPIError: LocalizedError, Equatable, Sendable {
    case signedOut
    case forbidden
    case notFound
    case rateLimited(Int?)
    case server(Int)
    case invalidResponse
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .signedOut: return "The Roblox sign-in has expired."
        case .forbidden: return "Roblox did not allow this account to read that information."
        case .notFound: return "Roblox could not find that player."
        case .rateLimited(let seconds):
            if let seconds, seconds > 0 { return "Roblox is limiting requests. Try again after \(seconds) seconds." }
            return "Roblox is limiting requests. Try again in a minute."
        case .server(let status): return "Roblox returned server error \(status)."
        case .invalidResponse: return "Roblox returned information that this app could not read."
        case .networkUnavailable: return "The Roblox service could not be reached."
        }
    }
}

public protocol RobloxSocialProviding: Sendable {
    func friends(of userID: Int64) async throws -> [RobloxSocialUser]
    func users(for userIDs: [Int64]) async throws -> [RobloxSocialUser]
    func onlineFriends(of userID: Int64, session: String) async throws -> [RobloxVisibleFriend]
    func presences(for userIDs: [Int64], session: String?) async throws -> [RobloxSocialPresence]
}

public struct RobloxSocialAPIClient: RobloxSocialProviding, Sendable {
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
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    public func friends(of userID: Int64) async throws -> [RobloxSocialUser] {
        let url = URL(string: "https://friends.roblox.com/v1/users/\(userID)/friends")!
        var request = URLRequest(url: url)
        applyPublicHeaders(to: &request)
        let data = try await responseData(for: request, safeRead: true)
        do { return try decoder.decode(FriendResponse.self, from: data).data }
        catch { throw RobloxSocialAPIError.invalidResponse }
    }

    public func users(for userIDs: [Int64]) async throws -> [RobloxSocialUser] {
        guard !userIDs.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://users.roblox.com/v1/users")!)
        request.httpMethod = "POST"
        applyPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userIds": userIDs,
            "excludeBannedUsers": false
        ])
        let data = try await responseData(for: request, safeRead: true)
        do { return try decoder.decode(FriendResponse.self, from: data).data }
        catch { throw RobloxSocialAPIError.invalidResponse }
    }

    public func onlineFriends(of userID: Int64, session rawSession: String) async throws -> [RobloxVisibleFriend] {
        let url = URL(string: "https://friends.roblox.com/v1/users/\(userID)/friends/online")!
        var request = URLRequest(url: url)
        applyPublicHeaders(to: &request)
        applyCookie(rawSession, to: &request)
        let data = try await responseData(for: request, safeRead: false)
        if let response = try? decoder.decode(OnlineFriendResponse.self, from: data) {
            return response.data
        }
        if let response = try? decoder.decode([RobloxVisibleFriend].self, from: data) {
            return response
        }
        throw RobloxSocialAPIError.invalidResponse
    }

    public func presences(for userIDs: [Int64], session rawSession: String? = nil) async throws -> [RobloxSocialPresence] {
        guard !userIDs.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://presence.roblox.com/v1/presence/users")!)
        request.httpMethod = "POST"
        applyPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let rawSession { applyCookie(rawSession, to: &request) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userIds": userIDs])
        let data = try await responseData(for: request, safeRead: true)
        do { return try decoder.decode(PresenceResponse.self, from: data).userPresences }
        catch { throw RobloxSocialAPIError.invalidResponse }
    }

    private func responseData(for request: URLRequest, safeRead: Bool) async throws -> Data {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw RobloxSocialAPIError.invalidResponse }
                switch http.statusCode {
                case 200...299: return data
                case 401: throw RobloxSocialAPIError.signedOut
                case 403: throw RobloxSocialAPIError.forbidden
                case 404: throw RobloxSocialAPIError.notFound
                case 429:
                    let retry = retryAfter(from: http)
                    if safeRead, attempt < 2 {
                        attempt += 1
                        let delay = min(retry ?? (1 << attempt), 5)
                        try await Task.sleep(nanoseconds: UInt64(max(1, delay)) * 1_000_000_000)
                        continue
                    }
                    throw RobloxSocialAPIError.rateLimited(retry)
                case 500...599:
                    if safeRead, attempt < 2 {
                        attempt += 1
                        try await Task.sleep(nanoseconds: UInt64(1 << attempt) * 250_000_000)
                        continue
                    }
                    throw RobloxSocialAPIError.server(http.statusCode)
                default: throw RobloxSocialAPIError.server(http.statusCode)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RobloxSocialAPIError {
                throw error
            } catch {
                throw RobloxSocialAPIError.networkUnavailable
            }
        }
    }

    private func applyPublicHeaders(to request: inout URLRequest) {
        request.setValue("Roblox Account Manager for Mac/0.5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func applyCookie(_ rawSession: String, to request: inout URLRequest) {
        let value = RobloxAPIClient.normalizedCookie(from: rawSession)
        request.setValue(".ROBLOSECURITY=\(value)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.roblox.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.roblox.com/", forHTTPHeaderField: "Referer")
    }

    private func retryAfter(from response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            ?? response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Int.init)
    }
}

private struct FriendResponse: Decodable { let data: [RobloxSocialUser] }
private struct OnlineFriendResponse: Decodable { let data: [RobloxVisibleFriend] }
private struct PresenceResponse: Decodable { let userPresences: [RobloxSocialPresence] }

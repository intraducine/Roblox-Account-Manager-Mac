import Foundation

public struct RobloxPublicServer: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let maxPlayers: Int
    public let playing: Int
    public let fps: Double?
    public let ping: Int?

    public init(id: String, maxPlayers: Int, playing: Int, fps: Double? = nil, ping: Int? = nil) {
        self.id = id
        self.maxPlayers = maxPlayers
        self.playing = playing
        self.fps = fps
        self.ping = ping
    }

    public var openSpaces: Int {
        max(0, maxPlayers - playing)
    }
}

public struct RobloxPublicServerPage: Decodable, Equatable, Sendable {
    public let previousPageCursor: String?
    public let nextPageCursor: String?
    public let data: [RobloxPublicServer]

    public init(previousPageCursor: String? = nil, nextPageCursor: String? = nil, data: [RobloxPublicServer]) {
        self.previousPageCursor = previousPageCursor
        self.nextPageCursor = nextPageCursor
        self.data = data
    }
}

public struct RobloxUserSearchResult: Decodable, Equatable, Sendable {
    public let requestedUsername: String?
    public let id: Int64
    public let name: String
    public let displayName: String

    public init(requestedUsername: String? = nil, id: Int64, name: String, displayName: String) {
        self.requestedUsername = requestedUsername
        self.id = id
        self.name = name
        self.displayName = displayName
    }
}

public struct RobloxUserPresence: Decodable, Equatable, Sendable {
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

public enum RobloxServerSelection: Equatable, Sendable {
    case automatic
    case publicInstance(jobID: String, playing: Int, maxPlayers: Int)
    case player(username: String, userID: Int64, jobID: String)
    case privateLink(String)
    case manualJob(String)

    public static func savedValue(_ value: String) -> RobloxServerSelection {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .automatic }
        if RobloxLaunchURLBuilder.privateLinkCode(from: clean) != nil
            || RobloxLaunchURLBuilder.privateShareCode(from: clean) != nil {
            return .privateLink(clean)
        }
        return .manualJob(clean)
    }

    public var persistedValue: String {
        switch self {
        case .automatic, .publicInstance, .player, .manualJob:
            return ""
        case .privateLink(let link):
            return link.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public var jobIDValue: String {
        switch self {
        case .publicInstance(let jobID, _, _), .player(_, _, let jobID), .manualJob(let jobID):
            return jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        case .automatic, .privateLink:
            return ""
        }
    }
}

public struct RobloxWebLaunchRequest: Equatable, Sendable {
    public let placeID: Int64
    public let server: RobloxServerSelection

    public init(placeID: Int64, server: RobloxServerSelection) {
        self.placeID = placeID
        self.server = server
    }
}

public enum RobloxWebLaunchRequestParser {
    public static func isRobloxLaunchURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "roblox-player" || scheme == "roblox"
    }

    public static func parse(_ url: URL) -> RobloxWebLaunchRequest? {
        guard isRobloxLaunchURL(url) else { return nil }
        if url.scheme?.lowercased() == "roblox",
           let direct = parseDirectRobloxURL(url) {
            return direct
        }

        let marker = "placelauncherurl:"
        guard let field = url.absoluteString
            .split(separator: "+", omittingEmptySubsequences: false)
            .first(where: { $0.lowercased().hasPrefix(marker) }) else {
            return nil
        }
        var launcherText = String(field.dropFirst(marker.count))
        for _ in 0..<2 {
            guard let decoded = launcherText.removingPercentEncoding,
                  decoded != launcherText else { break }
            launcherText = decoded
        }
        guard let components = URLComponents(string: launcherText),
              components.scheme?.lowercased() == "https",
              isLauncherHost(components.host),
              components.path.lowercased() == "/game/placelauncher.ashx" else {
            return nil
        }

        let values = Dictionary(
            components.queryItems?.map { ($0.name.lowercased(), $0.value ?? "") } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        guard let placeID = Int64(values["placeid"] ?? ""), placeID > 0 else { return nil }

        switch values["request"]?.lowercased() {
        case "requestgame":
            return RobloxWebLaunchRequest(placeID: placeID, server: .automatic)
        case "requestgamejob":
            guard let jobID = clean(values["gameid"]), !jobID.isEmpty else { return nil }
            return RobloxWebLaunchRequest(placeID: placeID, server: .manualJob(jobID))
        case "requestprivategame":
            guard let linkCode = clean(values["linkcode"]), !linkCode.isEmpty,
                  let link = privateServerLink(placeID: placeID, linkCode: linkCode) else {
                return nil
            }
            return RobloxWebLaunchRequest(placeID: placeID, server: .privateLink(link))
        default:
            return nil
        }
    }

    private static func parseDirectRobloxURL(_ url: URL) -> RobloxWebLaunchRequest? {
        let raw = url.absoluteString
        guard let separator = raw.firstIndex(of: ":") else { return nil }
        var payload = String(raw[raw.index(after: separator)...])
        if payload.hasPrefix("//") { payload.removeFirst(2) }
        let fields = payload.split(separator: "&", omittingEmptySubsequences: false)
        guard let placeField = fields.first(where: {
            $0.lowercased().hasPrefix("placeid=")
        }),
        let equals = placeField.firstIndex(of: "="),
        let placeID = Int64(placeField[placeField.index(after: equals)...]),
        placeID > 0 else { return nil }
        return RobloxWebLaunchRequest(placeID: placeID, server: .automatic)
    }

    private static func isLauncherHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "www.roblox.com"
            || host == "assetgame.roblox.com"
            || host == "gamejoin.roblox.com"
    }

    private static func clean(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func privateServerLink(placeID: Int64, linkCode: String) -> String? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.roblox.com"
        components.path = "/games/\(placeID)"
        components.queryItems = [URLQueryItem(name: "privateServerLinkCode", value: linkCode)]
        return components.url?.absoluteString
    }
}

struct RobloxUserSearchResponse: Decodable {
    let data: [RobloxUserSearchResult]
}

struct RobloxPresenceResponse: Decodable {
    let userPresences: [RobloxUserPresence]
}

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
        case .automatic, .publicInstance, .player:
            return ""
        case .privateLink(let link):
            return link.trimmingCharacters(in: .whitespacesAndNewlines)
        case .manualJob(let jobID):
            return jobID.trimmingCharacters(in: .whitespacesAndNewlines)
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

struct RobloxUserSearchResponse: Decodable {
    let data: [RobloxUserSearchResult]
}

struct RobloxPresenceResponse: Decodable {
    let userPresences: [RobloxUserPresence]
}

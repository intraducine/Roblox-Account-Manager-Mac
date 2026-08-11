import Foundation

public enum RobloxPresenceType: Int, Codable, Sendable {
    case offline = 0
    case online = 1
    case inExperience = 2
    case inStudio = 3
    case invisible = 4
    case unknown = -1

    public init(rawPresenceType: Int) {
        self = Self(rawValue: rawPresenceType) ?? .unknown
    }
}

public struct PlayerCandidate: Identifiable, Equatable, Sendable {
    public var id: Int64 { userID }
    public let userID: Int64
    public var username: String
    public var displayName: String
    public var avatarURL: URL?
    public var sourceAccountIDs: Set<UUID>

    public init(
        userID: Int64,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        sourceAccountIDs: Set<UUID> = []
    ) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.sourceAccountIDs = sourceAccountIDs
    }
}

public struct PlayerPresenceSnapshot: Equatable, Sendable {
    public let userID: Int64
    public let presenceType: RobloxPresenceType
    public let placeID: Int64?
    public let rootPlaceID: Int64?
    public let universeID: Int64?
    public let jobID: String?
    public let locationName: String?
    public let observedAt: Date

    public init(
        userID: Int64,
        presenceType: RobloxPresenceType,
        placeID: Int64? = nil,
        rootPlaceID: Int64? = nil,
        universeID: Int64? = nil,
        jobID: String? = nil,
        locationName: String? = nil,
        observedAt: Date = Date()
    ) {
        self.userID = userID
        self.presenceType = presenceType
        self.placeID = placeID
        self.rootPlaceID = rootPlaceID
        self.universeID = universeID
        self.jobID = jobID
        self.locationName = locationName
        self.observedAt = observedAt
    }
}

public enum PublicServerVerification: Equatable, Sendable {
    case noServerSupplied
    case friendTarget
    case verifiedPublic(RobloxPublicServer)
    case restrictedOrUnavailable
    case unconfirmed(pagesSearched: Int)
    case paused(pagesSearched: Int, retryAfter: Int?)
    case verificationFailed(String)

    public var isVerifiedPublic: Bool {
        if case .verifiedPublic = self { return true }
        return false
    }

    public var allowsDirectJoinAttempt: Bool {
        switch self {
        case .friendTarget, .verifiedPublic: return true
        default: return false
        }
    }
}

public struct PlayerDiscoverySource: Sendable {
    public let account: ManagedAccount
    public let session: String

    public init(account: ManagedAccount, session: String) {
        self.account = account
        self.session = session
    }
}

public struct DiscoveredPlayer: Identifiable, Equatable, Sendable {
    public var id: Int64 { candidate.userID }
    public var candidate: PlayerCandidate
    public var presence: PlayerPresenceSnapshot
    public var verification: PublicServerVerification
    public var isPubliclyVisible: Bool
    public var conflictingPresenceWasObserved: Bool

    public init(
        candidate: PlayerCandidate,
        presence: PlayerPresenceSnapshot,
        verification: PublicServerVerification = .noServerSupplied,
        isPubliclyVisible: Bool = true,
        conflictingPresenceWasObserved: Bool = false
    ) {
        self.candidate = candidate
        self.presence = presence
        self.verification = verification
        self.isPubliclyVisible = isPubliclyVisible
        self.conflictingPresenceWasObserved = conflictingPresenceWasObserved
    }
}

public struct PlayerDiscoveryFailure: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let accountID: UUID?
    public let message: String

    public init(id: UUID = UUID(), accountID: UUID? = nil, message: String) {
        self.id = id
        self.accountID = accountID
        self.message = message
    }
}

public struct PlayerDiscoveryResult: Equatable, Sendable {
    public var players: [DiscoveredPlayer]
    public var failures: [PlayerDiscoveryFailure]
    public var completedAt: Date
    public var usedPublicPresenceOnly: Bool

    public init(
        players: [DiscoveredPlayer] = [],
        failures: [PlayerDiscoveryFailure] = [],
        completedAt: Date = Date(),
        usedPublicPresenceOnly: Bool = true
    ) {
        self.players = players
        self.failures = failures
        self.completedAt = completedAt
        self.usedPublicPresenceOnly = usedPublicPresenceOnly
    }
}

public struct PlayerDiscoveryConfiguration: Equatable, Sendable {
    public var presenceBatchSize: Int
    public var maximumConcurrentRequests: Int
    public var cacheLifetime: TimeInterval
    public var maximumServerPages: Int

    public init(
        presenceBatchSize: Int = 50,
        maximumConcurrentRequests: Int = 2,
        cacheLifetime: TimeInterval = 60,
        maximumServerPages: Int = 3
    ) {
        self.presenceBatchSize = max(1, presenceBatchSize)
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.cacheLifetime = max(0, cacheLifetime)
        self.maximumServerPages = max(1, maximumServerPages)
    }
}

public enum AccountHealth: Equatable, Sendable {
    case unchecked
    case checking
    case ready(lastChecked: Date)
    case signedOut
    case wrongAccount(actualUserID: Int64)
    case networkUnavailable

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public enum AccountJoinState: String, Codable, Sendable {
    case expectedToJoin
    case alreadyRunning
    case signedOut
    case serverHasNoSpace
    case statusUnknown
}

public struct AccountJoinAssessment: Identifiable, Equatable, Sendable {
    public var id: UUID { accountID }
    public let accountID: UUID
    public let state: AccountJoinState
    public let explanation: String

    public init(accountID: UUID, state: AccountJoinState, explanation: String) {
        self.accountID = accountID
        self.state = state
        self.explanation = explanation
    }
}

public struct PlayerJoinTarget: Equatable, Sendable {
    public let placeID: Int64
    public let jobID: String
    public let verification: PublicServerVerification

    public init(placeID: Int64, jobID: String, verification: PublicServerVerification) {
        self.placeID = placeID
        self.jobID = jobID
        self.verification = verification
    }
}

public protocol PlayerDiscovering: Sendable {
    func discover(sources: [PlayerDiscoverySource]) async -> PlayerDiscoveryResult
    func continueVerification(for player: DiscoveredPlayer) async -> PublicServerVerification
    func refreshVerification(for player: DiscoveredPlayer) async -> PublicServerVerification
    func clearCache() async
}

public extension PlayerDiscovering {
    func continueVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        player.verification
    }

    func refreshVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        player.verification
    }

    func clearCache() async {}
}

public protocol JoinAssessing: Sendable {
    func assess(
        target: PlayerJoinTarget,
        accounts: [ManagedAccount],
        health: [UUID: AccountHealth],
        runningAccountIDs: Set<UUID>
    ) async -> [AccountJoinAssessment]
}

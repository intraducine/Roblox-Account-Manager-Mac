import Foundation

public struct FriendRelayPlan: Equatable, Sendable {
    public let sourceAccountIDs: Set<UUID>
    public let friendAccountIDs: [UUID: Set<UUID>]
    public let levels: [UUID: Int]
    public let lookupFailures: [UUID: String]

    public init(
        sourceAccountIDs: Set<UUID>,
        friendAccountIDs: [UUID: Set<UUID>],
        levels: [UUID: Int],
        lookupFailures: [UUID: String] = [:]
    ) {
        self.sourceAccountIDs = sourceAccountIDs
        self.friendAccountIDs = friendAccountIDs
        self.levels = levels
        self.lookupFailures = lookupFailures
    }

    public func availableParent(for accountID: UUID, joinedAccountIDs: Set<UUID>) -> UUID? {
        friendAccountIDs[accountID, default: []]
            .intersection(joinedAccountIDs)
            .sorted { left, right in
                let leftLevel = levels[left] ?? .max
                let rightLevel = levels[right] ?? .max
                if leftLevel != rightLevel { return leftLevel < rightLevel }
                return left.uuidString < right.uuidString
            }
            .first
    }
}

public enum FriendRelayArrival: Equatable, Sendable {
    case arrived
    case timedOut
    case unavailable(String)
}

public protocol FriendRelayProviding: Sendable {
    func plan(accounts: [ManagedAccount], sourceAccountIDs: Set<UUID>) async -> FriendRelayPlan
    func waitForServer(
        account: ManagedAccount,
        session: String,
        placeID: Int64,
        jobID: String
    ) async -> FriendRelayArrival
}

public struct FriendRelayConfiguration: Equatable, Sendable {
    public var presenceAttempts: Int
    public var presencePollNanoseconds: UInt64
    public var confirmationTimeoutNanoseconds: UInt64

    public init(
        presenceAttempts: Int = 15,
        presencePollNanoseconds: UInt64 = 1_000_000_000,
        confirmationTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.presenceAttempts = max(1, presenceAttempts)
        self.presencePollNanoseconds = presencePollNanoseconds
        self.confirmationTimeoutNanoseconds = max(1, confirmationTimeoutNanoseconds)
    }
}

public actor FriendRelayService: FriendRelayProviding {
    private let social: any RobloxSocialProviding
    private let configuration: FriendRelayConfiguration

    public init(
        social: any RobloxSocialProviding = RobloxSocialAPIClient(),
        configuration: FriendRelayConfiguration = FriendRelayConfiguration()
    ) {
        self.social = social
        self.configuration = configuration
    }

    public func plan(
        accounts: [ManagedAccount],
        sourceAccountIDs: Set<UUID>
    ) async -> FriendRelayPlan {
        let selectedIDs = Set(accounts.map(\.id))
        let roots = sourceAccountIDs.intersection(selectedIDs)
        let accountIDByUserID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.userID, $0.id) })
        var friends = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Set<UUID>()) })
        var failures: [UUID: String] = [:]

        for account in accounts {
            do {
                let selectedFriends = try await social.friends(of: account.userID).compactMap {
                    accountIDByUserID[$0.id]
                }
                for friendID in selectedFriends where friendID != account.id {
                    // Roblox friendships are mutual. Fill both sides so one temporary lookup
                    // failure does not erase a relationship returned by the other account.
                    friends[account.id, default: []].insert(friendID)
                    friends[friendID, default: []].insert(account.id)
                }
            } catch {
                failures[account.id] = error.localizedDescription
            }
        }

        var levels = Dictionary(uniqueKeysWithValues: roots.map { ($0, 0) })
        var frontier = roots
        var level = 0
        while !frontier.isEmpty {
            level += 1
            var next = Set<UUID>()
            for accountID in selectedIDs where levels[accountID] == nil {
                if !friends[accountID, default: []].isDisjoint(with: frontier) {
                    levels[accountID] = level
                    next.insert(accountID)
                }
            }
            frontier = next
        }

        return FriendRelayPlan(
            sourceAccountIDs: roots,
            friendAccountIDs: friends,
            levels: levels,
            lookupFailures: failures
        )
    }

    public func waitForServer(
        account: ManagedAccount,
        session: String,
        placeID: Int64,
        jobID: String
    ) async -> FriendRelayArrival {
        let social = self.social
        let configuration = self.configuration
        return await withTaskGroup(of: FriendRelayArrival.self) { group in
            group.addTask {
                await Self.pollForServer(
                    social: social,
                    configuration: configuration,
                    account: account,
                    session: session,
                    placeID: placeID,
                    jobID: jobID
                )
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: configuration.confirmationTimeoutNanoseconds)
                    return .timedOut
                } catch {
                    return .unavailable("The friend relay was stopped.")
                }
            }

            let result = await group.next() ?? .timedOut
            group.cancelAll()
            return result
        }
    }

    private static func pollForServer(
        social: any RobloxSocialProviding,
        configuration: FriendRelayConfiguration,
        account: ManagedAccount,
        session: String,
        placeID: Int64,
        jobID: String
    ) async -> FriendRelayArrival {
        let cleanJobID = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        var lastError: Error?

        for attempt in 0..<configuration.presenceAttempts {
            do {
                let presence = try await social.presences(for: [account.userID], session: session)
                    .first(where: { $0.userId == account.userID })
                if presence?.userPresenceType == RobloxPresenceType.inExperience.rawValue,
                   presence?.placeId == placeID,
                   presence?.gameId?.caseInsensitiveCompare(cleanJobID) == .orderedSame {
                    return .arrived
                }
            } catch is CancellationError {
                return .unavailable("The friend relay was stopped.")
            } catch {
                lastError = error
                if error as? RobloxSocialAPIError == .signedOut {
                    return .unavailable(error.localizedDescription)
                }
            }

            if attempt + 1 < configuration.presenceAttempts,
               configuration.presencePollNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: configuration.presencePollNanoseconds)
                } catch {
                    return .unavailable("The friend relay was stopped.")
                }
            }
        }

        if let lastError {
            return .unavailable(lastError.localizedDescription)
        }
        return .timedOut
    }
}

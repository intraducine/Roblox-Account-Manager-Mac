import Foundation

public protocol RobloxPublicServerProviding: Sendable {
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage
}

extension RobloxAPIClient: RobloxPublicServerProviding {}

public actor PlayerDiscoveryService {
    private struct FriendCacheEntry: Sendable {
        let friends: [RobloxVisibleFriend]
        let fetchedAt: Date
    }

    private let social: any RobloxSocialProviding
    private let configuration: PlayerDiscoveryConfiguration
    private var friendCache: [UUID: FriendCacheEntry] = [:]

    public init(
        social: any RobloxSocialProviding,
        configuration: PlayerDiscoveryConfiguration = PlayerDiscoveryConfiguration()
    ) {
        self.social = social
        self.configuration = configuration
    }

    public func discover(sources: [PlayerDiscoverySource]) async -> PlayerDiscoveryResult {
        guard !sources.isEmpty else { return PlayerDiscoveryResult(usedPublicPresenceOnly: false) }
        var candidates: [Int64: PlayerCandidate] = [:]
        var snapshots: [Int64: PlayerPresenceSnapshot] = [:]
        var conflictingUserIDs = Set<Int64>()
        var failures: [PlayerDiscoveryFailure] = []
        let now = Date()

        for source in sources where !Task.isCancelled {
            let visibleFriends: [RobloxVisibleFriend]
            if let cached = friendCache[source.account.id],
               now.timeIntervalSince(cached.fetchedAt) < configuration.cacheLifetime {
                visibleFriends = cached.friends
            } else {
                do {
                    visibleFriends = try await social.onlineFriends(
                        of: source.account.userID,
                        session: source.session
                    )
                    friendCache[source.account.id] = FriendCacheEntry(friends: visibleFriends, fetchedAt: now)
                } catch {
                    failures.append(PlayerDiscoveryFailure(
                        accountID: source.account.id,
                        message: error.localizedDescription
                    ))
                    continue
                }
            }

            for friend in visibleFriends {
                let presenceType = RobloxPresenceType(rawPresenceType: friend.userPresenceType ?? 0)
                guard presenceType == .inExperience else { continue }
                if var candidate = candidates[friend.id] {
                    candidate.sourceAccountIDs.insert(source.account.id)
                    if candidate.username.isEmpty { candidate.username = friend.name }
                    if candidate.displayName.isEmpty { candidate.displayName = friend.displayName }
                    candidates[friend.id] = candidate
                } else {
                    candidates[friend.id] = PlayerCandidate(
                        userID: friend.id,
                        username: friend.name,
                        displayName: friend.displayName,
                        sourceAccountIDs: [source.account.id]
                    )
                }

                let snapshot = PlayerPresenceSnapshot(
                    userID: friend.id,
                    presenceType: presenceType,
                    placeID: friend.placeId,
                    rootPlaceID: friend.rootPlaceId,
                    universeID: friend.universeId,
                    jobID: friend.gameId,
                    locationName: friend.lastLocation,
                    observedAt: now
                )
                if let current = snapshots[friend.id] {
                    if current.placeID != snapshot.placeID || current.jobID != snapshot.jobID {
                        conflictingUserIDs.insert(friend.id)
                    }
                    if completeness(of: snapshot) > completeness(of: current) {
                        snapshots[friend.id] = snapshot
                    }
                } else {
                    snapshots[friend.id] = snapshot
                }
            }
        }

        let missingProfileIDs = candidates.values.filter {
            $0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.userID).sorted()
        for batchStart in stride(from: 0, to: missingProfileIDs.count, by: configuration.presenceBatchSize) {
            let batch = Array(missingProfileIDs[
                batchStart..<min(batchStart + configuration.presenceBatchSize, missingProfileIDs.count)
            ])
            do {
                for profile in try await social.users(for: batch) {
                    guard var candidate = candidates[profile.id] else { continue }
                    candidate.username = profile.name
                    candidate.displayName = profile.displayName
                    candidates[profile.id] = candidate
                }
            } catch {
                failures.append(PlayerDiscoveryFailure(message: "Player names could not load. \(error.localizedDescription)"))
            }
        }
        for userID in candidates.keys {
            guard var candidate = candidates[userID] else { continue }
            if candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                candidate.displayName = candidate.username.isEmpty ? "Roblox user \(userID)" : candidate.username
            }
            candidates[userID] = candidate
        }

        var players: [DiscoveredPlayer] = []
        for snapshot in snapshots.values {
            guard let candidate = candidates[snapshot.userID] else { continue }
            let verification: PublicServerVerification = snapshot.placeID != nil
                && !(snapshot.jobID ?? "").isEmpty ? .friendTarget : .noServerSupplied
            players.append(DiscoveredPlayer(
                candidate: candidate,
                presence: snapshot,
                verification: verification,
                isPubliclyVisible: false,
                conflictingPresenceWasObserved: conflictingUserIDs.contains(snapshot.userID)
            ))
        }
        players.sort {
            ($0.candidate.displayName, $0.candidate.username)
                < ($1.candidate.displayName, $1.candidate.username)
        }
        return PlayerDiscoveryResult(players: players, failures: failures, usedPublicPresenceOnly: false)
    }

    public func continueVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        guard player.presence.placeID != nil, !(player.presence.jobID ?? "").isEmpty else {
            return .noServerSupplied
        }
        return .friendTarget
    }

    public func refreshVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        await continueVerification(for: player)
    }

    public func clearCache() async {
        friendCache.removeAll()
    }

    private func completeness(of presence: PlayerPresenceSnapshot) -> Int {
        [presence.placeID != nil, presence.jobID != nil, presence.universeID != nil, presence.locationName != nil]
            .filter { $0 }.count
    }
}

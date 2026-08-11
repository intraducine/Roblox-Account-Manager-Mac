import Foundation

public protocol RobloxPublicServerProviding: Sendable {
    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage
}

extension RobloxAPIClient: RobloxPublicServerProviding {}

public actor PublicServerVerificationService {
    private struct CacheEntry: Sendable {
        let page: RobloxPublicServerPage
        let fetchedAt: Date
    }

    private let provider: any RobloxPublicServerProviding
    private let configuration: PlayerDiscoveryConfiguration
    private var cache: [String: CacheEntry] = [:]

    public init(
        provider: any RobloxPublicServerProviding,
        configuration: PlayerDiscoveryConfiguration = PlayerDiscoveryConfiguration()
    ) {
        self.provider = provider
        self.configuration = configuration
    }

    public func verify(
        placeID: Int64,
        jobID: String,
        continuePastBudget: Bool = false,
        forceRefresh: Bool = false
    ) async -> PublicServerVerification {
        let cleanJobID = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard placeID > 0, !cleanJobID.isEmpty else { return .noServerSupplied }

        let pageLimit = continuePastBudget ? 100 : configuration.maximumServerPages
        var cursor: String?
        var searched = 0
        do {
            while searched < pageLimit {
                try Task.checkCancellation()
                let page = try await page(placeID: placeID, cursor: cursor, forceRefresh: forceRefresh)
                searched += 1
                if let server = page.data.first(where: { $0.id.caseInsensitiveCompare(cleanJobID) == .orderedSame }) {
                    return .verifiedPublic(server)
                }
                guard let next = page.nextPageCursor, !next.isEmpty else {
                    return .restrictedOrUnavailable
                }
                cursor = next
            }
            return .unconfirmed(pagesSearched: searched)
        } catch is CancellationError {
            return .verificationFailed("Checking stopped.")
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
    }

    public func clearCache() {
        cache.removeAll()
    }

    private func page(placeID: Int64, cursor: String?, forceRefresh: Bool) async throws -> RobloxPublicServerPage {
        let key = "\(placeID):\(cursor ?? "first")"
        if !forceRefresh,
           let cached = cache[key],
           Date().timeIntervalSince(cached.fetchedAt) < configuration.cacheLifetime {
            return cached.page
        }
        let page = try await provider.publicServers(placeID: placeID, cursor: cursor)
        cache[key] = CacheEntry(page: page, fetchedAt: Date())
        return page
    }
}

public actor PlayerDiscoveryService: PlayerDiscovering {
    private struct PresenceCacheEntry: Sendable {
        let presence: RobloxSocialPresence
        let fetchedAt: Date
    }

    private let social: any RobloxSocialProviding
    private let verifier: PublicServerVerificationService
    private let configuration: PlayerDiscoveryConfiguration
    private var presenceCache: [Int64: PresenceCacheEntry] = [:]

    public init(
        social: any RobloxSocialProviding,
        serverProvider: any RobloxPublicServerProviding,
        configuration: PlayerDiscoveryConfiguration = PlayerDiscoveryConfiguration()
    ) {
        self.social = social
        self.verifier = PublicServerVerificationService(provider: serverProvider, configuration: configuration)
        self.configuration = configuration
    }

    public func discover(sourceAccounts: [ManagedAccount]) async -> PlayerDiscoveryResult {
        guard !sourceAccounts.isEmpty else { return PlayerDiscoveryResult() }
        var candidates: [Int64: PlayerCandidate] = [:]
        var failures: [PlayerDiscoveryFailure] = []

        var nextSource = 0
        while nextSource < sourceAccounts.count, !Task.isCancelled {
            let end = min(nextSource + configuration.maximumConcurrentRequests, sourceAccounts.count)
            let sourceBatch = Array(sourceAccounts[nextSource..<end])
            await withTaskGroup(of: (ManagedAccount, Result<[RobloxSocialUser], Error>).self) { group in
                for account in sourceBatch {
                    group.addTask { [social] in
                        do { return (account, .success(try await social.friends(of: account.userID))) }
                        catch { return (account, .failure(error)) }
                    }
                }
                for await (account, result) in group {
                    switch result {
                    case .success(let friends):
                        for friend in friends {
                            if var candidate = candidates[friend.id] {
                                candidate.sourceAccountIDs.insert(account.id)
                                candidates[friend.id] = candidate
                            } else {
                                candidates[friend.id] = PlayerCandidate(
                                    userID: friend.id,
                                    username: friend.name,
                                    displayName: friend.displayName,
                                    sourceAccountIDs: [account.id]
                                )
                            }
                        }
                    case .failure(let error):
                        failures.append(PlayerDiscoveryFailure(accountID: account.id, message: error.localizedDescription))
                    }
                }
            }
            nextSource = end
        }

        let missingProfileIDs = candidates.values.filter {
            $0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.userID).sorted()
        if !missingProfileIDs.isEmpty {
            let profileBatches = stride(
                from: 0,
                to: missingProfileIDs.count,
                by: configuration.presenceBatchSize
            ).map {
                Array(missingProfileIDs[$0..<min($0 + configuration.presenceBatchSize, missingProfileIDs.count)])
            }
            for batch in profileBatches where !Task.isCancelled {
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
        }
        for userID in candidates.keys {
            guard var candidate = candidates[userID] else { continue }
            if candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                candidate.displayName = candidate.username.isEmpty ? "Roblox user \(userID)" : candidate.username
            }
            candidates[userID] = candidate
        }

        let ids = candidates.keys.sorted()
        let rawPresences = await loadPublicPresences(userIDs: ids, failures: &failures)
        var presences: [Int64: RobloxSocialPresence] = [:]
        var conflictingUserIDs = Set<Int64>()
        for presence in rawPresences {
            if let current = presences[presence.userId] {
                if current.placeId != presence.placeId || current.gameId != presence.gameId {
                    conflictingUserIDs.insert(presence.userId)
                }
                if completeness(of: presence) > completeness(of: current) {
                    presences[presence.userId] = presence
                }
            } else {
                presences[presence.userId] = presence
            }
        }
        var players: [DiscoveredPlayer] = []
        for presence in presences.values where RobloxPresenceType(rawPresenceType: presence.userPresenceType) == .inExperience {
            guard let candidate = candidates[presence.userId] else { continue }
            let snapshot = PlayerPresenceSnapshot(
                userID: presence.userId,
                presenceType: RobloxPresenceType(rawPresenceType: presence.userPresenceType),
                placeID: presence.placeId,
                rootPlaceID: presence.rootPlaceId,
                universeID: presence.universeId,
                jobID: presence.gameId,
                locationName: presence.lastLocation
            )
            let verification: PublicServerVerification
            if let placeID = snapshot.placeID, let jobID = snapshot.jobID, !jobID.isEmpty {
                verification = await verifier.verify(placeID: placeID, jobID: jobID)
            } else {
                verification = .noServerSupplied
            }
            players.append(DiscoveredPlayer(
                candidate: candidate,
                presence: snapshot,
                verification: verification,
                isPubliclyVisible: true,
                conflictingPresenceWasObserved: conflictingUserIDs.contains(presence.userId)
            ))
        }
        players.sort {
            ($0.candidate.displayName, $0.candidate.username)
                < ($1.candidate.displayName, $1.candidate.username)
        }
        return PlayerDiscoveryResult(players: players, failures: failures, usedPublicPresenceOnly: true)
    }

    public func continueVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        guard let placeID = player.presence.placeID, let jobID = player.presence.jobID else {
            return .noServerSupplied
        }
        return await verifier.verify(placeID: placeID, jobID: jobID, continuePastBudget: true)
    }

    public func refreshVerification(for player: DiscoveredPlayer) async -> PublicServerVerification {
        guard let placeID = player.presence.placeID, let jobID = player.presence.jobID else {
            return .noServerSupplied
        }
        return await verifier.verify(placeID: placeID, jobID: jobID, forceRefresh: true)
    }

    public func clearCache() async {
        presenceCache.removeAll()
        await verifier.clearCache()
    }

    private func loadPublicPresences(
        userIDs: [Int64],
        failures: inout [PlayerDiscoveryFailure]
    ) async -> [RobloxSocialPresence] {
        let now = Date()
        var result: [RobloxSocialPresence] = []
        var uncached: [Int64] = []
        for userID in userIDs {
            if let cached = presenceCache[userID],
               now.timeIntervalSince(cached.fetchedAt) < configuration.cacheLifetime {
                result.append(cached.presence)
            } else {
                uncached.append(userID)
            }
        }

        let batches = stride(from: 0, to: uncached.count, by: configuration.presenceBatchSize).map {
            Array(uncached[$0..<min($0 + configuration.presenceBatchSize, uncached.count)])
        }
        var nextBatch = 0
        while nextBatch < batches.count {
            let end = min(nextBatch + configuration.maximumConcurrentRequests, batches.count)
            let slice = Array(batches[nextBatch..<end])
            await withTaskGroup(of: Result<[RobloxSocialPresence], Error>.self) { group in
                for batch in slice {
                    group.addTask { [social] in
                        do { return .success(try await social.presences(for: batch, session: nil)) }
                        catch { return .failure(error) }
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .success(let values):
                        for value in values {
                            presenceCache[value.userId] = PresenceCacheEntry(presence: value, fetchedAt: now)
                            result.append(value)
                        }
                    case .failure(let error):
                        failures.append(PlayerDiscoveryFailure(message: error.localizedDescription))
                    }
                }
            }
            nextBatch = end
        }
        return result
    }

    private func completeness(of presence: RobloxSocialPresence) -> Int {
        [presence.placeId != nil, presence.gameId != nil, presence.universeId != nil, presence.lastLocation != nil]
            .filter { $0 }.count
    }
}

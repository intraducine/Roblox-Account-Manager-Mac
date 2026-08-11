import Foundation
import RAMacCore

struct PublicServerSnapshot: Sendable {
    let page: RobloxPublicServerPage
    let fetchedAt: Date
}

struct JoinablePlayerServer: Sendable {
    let user: RobloxUserSearchResult
    let presence: RobloxUserPresence
}

@MainActor
final class AccountStore: ObservableObject {
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum BatchLaunchState: Equatable {
        case starting
        case failed(String)

        var label: String {
            switch self {
            case .starting: return "Starting"
            case .failed: return "Failed"
            }
        }

        var errorMessage: String? {
            guard case .failed(let message) = self else { return nil }
            return message
        }
    }

    private struct BatchOutcome: Sendable {
        let accountID: UUID
        let username: String
        let processIdentifier: Int32?
        let errorMessage: String?
    }

    @Published private(set) var accounts: [ManagedAccount] = []
    @Published var selectedID: UUID?
    @Published var search = ""
    @Published var isWorking = false
    @Published var notice: Notice?
    @Published var launchStatus = "Ready"
    @Published private(set) var runningAccountIDs = Set<UUID>()
    @Published private(set) var batchSelectedIDs = Set<UUID>()
    @Published private(set) var batchStates: [UUID: BatchLaunchState] = [:]
    @Published private(set) var isBatchLaunching = false
    @Published private(set) var isStoppingAll = false
    @Published private(set) var batchStatus = "Select accounts from the shelf"
    @Published private(set) var launchMode: RobloxLaunchMode
    @Published private(set) var groups: [String] = []
    @Published private(set) var discoveredPlayers: [DiscoveredPlayer] = []
    @Published private(set) var discoveryFailures: [PlayerDiscoveryFailure] = []
    @Published private(set) var discoveryUpdatedAt: Date?
    @Published private(set) var isDiscoveringPlayers = false
    @Published private(set) var accountHealth: [UUID: AccountHealth] = [:]
    @Published private(set) var launchSets: [LaunchSet] = []
    @Published private(set) var experiences: [ExperienceRecord] = []
    @Published private(set) var privateServers: [SavedPrivateServer] = []
    @Published private(set) var activeLaunchTargets: [UUID: ActiveLaunchTargetRecord] = [:]

    private let repository: AccountRepository
    private let vault: any SecretVault
    private let api: any RobloxAPIProviding
    private let builder: RobloxLaunchURLBuilder
    private let launcher: any ParallelRobloxLaunching
    private let playerDiscovery: any PlayerDiscovering
    private let joinAssessor: any JoinAssessing
    private let healthChecker: any AccountHealthChecking
    private let launchSetRepository: LaunchSetRepository
    private let experienceRepository: ExperienceLibraryRepository
    private let privateServerRepository: PrivateServerRepository
    private let activeLaunchRepository: ActiveLaunchTargetRepository
    private let archiveService = MetadataArchiveService()
    private let experienceLibrary = ExperienceLibrary()
    private var serverPageCache: [String: PublicServerSnapshot] = [:]
    private let serverCacheLifetime: TimeInterval = 60

    init(
        repository: AccountRepository = AccountRepository(),
        vault: any SecretVault = KeychainVault(),
        api: any RobloxAPIProviding = RobloxAPIClient(),
        builder: RobloxLaunchURLBuilder = RobloxLaunchURLBuilder(),
        launcher: (any ParallelRobloxLaunching)? = nil,
        launchMode: RobloxLaunchMode? = nil,
        playerDiscovery: (any PlayerDiscovering)? = nil,
        joinAssessor: (any JoinAssessing)? = nil,
        healthChecker: (any AccountHealthChecking)? = nil,
        launchSetRepository: LaunchSetRepository? = nil,
        experienceRepository: ExperienceLibraryRepository? = nil,
        privateServerRepository: PrivateServerRepository? = nil,
        activeLaunchRepository: ActiveLaunchTargetRepository? = nil
    ) {
        self.repository = repository
        self.vault = vault
        self.api = api
        self.builder = builder
        self.launcher = launcher ?? ParallelRobloxLauncher()
        self.playerDiscovery = playerDiscovery ?? PlayerDiscoveryService(
            social: RobloxSocialAPIClient()
        )
        self.joinAssessor = joinAssessor ?? JoinAssessmentService()
        self.healthChecker = healthChecker ?? AccountHealthService(vault: vault, api: api)
        self.launchSetRepository = launchSetRepository ?? LaunchSetRepository(dataDirectory: repository.dataDirectory)
        self.experienceRepository = experienceRepository ?? ExperienceLibraryRepository(dataDirectory: repository.dataDirectory)
        self.privateServerRepository = privateServerRepository ?? PrivateServerRepository(dataDirectory: repository.dataDirectory)
        self.activeLaunchRepository = activeLaunchRepository ?? ActiveLaunchTargetRepository(dataDirectory: repository.dataDirectory)
        self.launchMode = launchMode == .modifiedParallel ? .modifiedParallel : .unmodifiedParallel
        load()
    }

    func setLaunchMode(_ mode: RobloxLaunchMode) {
        guard !isWorking, !isBatchLaunching else { return }
        guard runningAccountIDs.isEmpty else {
            notice = Notice(
                title: "Stop Roblox before changing mode",
                message: "Use Stop All, then select \(mode.title)."
            )
            return
        }
        if mode == .modifiedParallel {
            launchMode = .modifiedParallel
            launchStatus = "Advanced fallback selected"
        } else {
            launchMode = .unmodifiedParallel
            launchStatus = "Recommended launch method selected"
        }
    }

    var selectedAccount: ManagedAccount? {
        guard let selectedID else { return nil }
        return accounts.first(where: { $0.id == selectedID })
    }

    func publicServerPage(
        placeID: Int64,
        cursor: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> PublicServerSnapshot {
        let key = "\(placeID):\(cursor ?? "first")"
        if !forceRefresh,
           let cached = serverPageCache[key],
           Date().timeIntervalSince(cached.fetchedAt) < serverCacheLifetime {
            return cached
        }
        let page = try await api.publicServers(placeID: placeID, cursor: cursor)
        let snapshot = PublicServerSnapshot(page: page, fetchedAt: Date())
        serverPageCache[key] = snapshot
        return snapshot
    }

    func joinableServer(for username: String) async throws -> JoinablePlayerServer {
        let user = try await api.user(named: username)
        let presence = try await api.presence(userID: user.id)
        return JoinablePlayerServer(user: user, presence: presence)
    }

    func verifyPublicServer(
        placeID: Int64,
        jobID: String,
        maximumPages: Int = 10,
        forceRefresh: Bool = false
    ) async -> PublicServerVerification {
        var cursor: String?
        var searched = 0
        do {
            while searched < maximumPages {
                try Task.checkCancellation()
                let snapshot = try await publicServerPage(
                    placeID: placeID,
                    cursor: cursor,
                    forceRefresh: forceRefresh
                )
                searched += 1
                if let server = snapshot.page.data.first(where: {
                    $0.id.caseInsensitiveCompare(jobID) == .orderedSame
                }) {
                    return .verifiedPublic(server)
                }
                guard let next = snapshot.page.nextPageCursor, !next.isEmpty else {
                    return .restrictedOrUnavailable
                }
                cursor = next
            }
            return .unconfirmed(pagesSearched: searched)
        } catch is CancellationError {
            return .verificationFailed("Checking stopped.")
        } catch RobloxAPIError.requestBudgetPaused(let retryAfter) {
            return .paused(pagesSearched: searched, retryAfter: retryAfter)
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
    }

    var filteredAccounts: [ManagedAccount] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = accounts.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard !needle.isEmpty else { return sorted }
        return sorted.filter {
            $0.username.localizedCaseInsensitiveContains(needle)
                || $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.alias.localizedCaseInsensitiveContains(needle)
                || $0.groups.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    var groupNames: [String] {
        ManagedAccount.normalizedGroups(groups + accounts.flatMap(\.groups))
    }

    func load() {
        do {
            accounts = try repository.load()
            var removedTemporaryServer = false
            for index in accounts.indices {
                guard case .manualJob = RobloxServerSelection.savedValue(accounts[index].savedServer) else {
                    continue
                }
                guard !accounts[index].savedServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                accounts[index].savedServer = ""
                removedTemporaryServer = true
            }
            if removedTemporaryServer {
                try repository.save(accounts)
            }
            groups = ManagedAccount.normalizedGroups(
                (try repository.loadGroups()) + accounts.flatMap(\.groups)
            )
            launchSets = (try? launchSetRepository.load()) ?? []
            experiences = (try? experienceRepository.load()) ?? []
            do {
                privateServers = sortedPrivateServers(try privateServerRepository.load())
                migrateExistingPrivateServers()
            } catch {
                privateServers = []
                notice = Notice(title: "Private servers could not load", message: error.localizedDescription)
            }
            activeLaunchTargets = Dictionary(
                uniqueKeysWithValues: ((try? activeLaunchRepository.load()) ?? []).map { ($0.accountID, $0) }
            )
            accountHealth = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, AccountHealth.unchecked) })
            if selectedID == nil { selectedID = accounts.first?.id }
            Task {
                await refreshAvatarURLs()
                await refreshRunningInstances()
                await launcher.removeStaleCopies()
            }
        } catch {
            notice = Notice(title: "Accounts could not load", message: error.localizedDescription)
        }
    }

    func isRunning(_ account: ManagedAccount) -> Bool {
        runningAccountIDs.contains(account.id)
    }

    func isBatchSelected(_ account: ManagedAccount) -> Bool {
        batchSelectedIDs.contains(account.id)
    }

    func toggleBatchSelection(_ account: ManagedAccount) {
        guard !isBatchLaunching, !isRunning(account) else { return }
        if batchSelectedIDs.remove(account.id) == nil {
            batchSelectedIDs.insert(account.id)
        }
        batchStates[account.id] = nil
        updateBatchSelectionStatus()
    }

    func toggleBatchGroup(_ group: String) {
        guard !isBatchLaunching else { return }
        let eligible = Set(accounts.lazy.filter { $0.belongs(to: group) && !self.isRunning($0) }.map(\.id))
        guard !eligible.isEmpty else { return }
        if eligible.isSubset(of: batchSelectedIDs) {
            batchSelectedIDs.subtract(eligible)
            for accountID in eligible { batchStates[accountID] = nil }
        } else {
            batchSelectedIDs.formUnion(eligible)
        }
        updateBatchSelectionStatus()
    }

    func isBatchGroupSelected(_ group: String) -> Bool {
        let eligible = Set(accounts.lazy.filter { $0.belongs(to: group) && !self.isRunning($0) }.map(\.id))
        return !eligible.isEmpty && eligible.isSubset(of: batchSelectedIDs)
    }

    func clearBatchSelection() {
        guard !isBatchLaunching else { return }
        batchSelectedIDs.removeAll()
        batchStates.removeAll()
        updateBatchSelectionStatus()
    }

    @discardableResult
    func createGroup(_ rawName: String, addingTo accountID: UUID? = nil) -> String? {
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            notice = Notice(title: "Enter a group name", message: "A group name cannot be empty.")
            return nil
        }
        let groupName = groupNames.first(where: {
            $0.caseInsensitiveCompare(cleanName) == .orderedSame
        }) ?? cleanName
        if !groups.contains(where: { $0.caseInsensitiveCompare(groupName) == .orderedSame }) {
            groups = ManagedAccount.normalizedGroups(groups + [groupName])
        }
        if let accountID,
           let index = accounts.firstIndex(where: { $0.id == accountID }),
           !accounts[index].belongs(to: groupName) {
            accounts[index].groups = ManagedAccount.normalizedGroups(accounts[index].groups + [groupName])
        }
        do {
            try repository.saveGroups(groups)
            if accountID != nil { try repository.save(accounts) }
            launchStatus = "Group saved"
            return groupName
        } catch {
            notice = Notice(title: "Group was not saved", message: error.localizedDescription)
            return nil
        }
    }

    func setMembership(of account: ManagedAccount, in group: String, isMember: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updated = accounts[index]
        if isMember {
            updated.groups = ManagedAccount.normalizedGroups(updated.groups + [group])
        } else {
            updated.groups.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        }
        update(updated)
    }

    func refreshRunningInstances() async {
        let previousIDs = runningAccountIDs
        let refreshedIDs = await launcher.runningAccountIDs(from: accounts.map(\.id))
        if refreshedIDs != runningAccountIDs {
            runningAccountIDs = refreshedIDs
        }
        if !previousIDs.isEmpty,
           refreshedIDs.isEmpty,
           !isWorking,
           !isBatchLaunching,
           !isStoppingAll {
            launchStatus = "Ready"
            batchStatus = "No managed Roblox clients are running"
        }
        let staleTargets = activeLaunchTargets.keys.filter { !refreshedIDs.contains($0) }
        if !staleTargets.isEmpty {
            for accountID in staleTargets { activeLaunchTargets[accountID] = nil }
            try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
        }
    }

    private func refreshAvatarURLs() async {
        var changed = false
        for accountID in accounts.map(\.id) {
            guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { continue }
            if let url = await api.avatarURL(userID: accounts[index].userID),
               accounts[index].avatarURLString != url.absoluteString {
                accounts[index].avatarURLString = url.absoluteString
                changed = true
            }
        }
        if changed { try? repository.save(accounts) }
    }

    func checkAccount(_ account: ManagedAccount) async {
        accountHealth[account.id] = .checking
        accountHealth[account.id] = await healthChecker.check(account)
    }

    func prepareWebsiteSession(accountID: UUID) async -> Bool {
        await readyWebsiteAccount(from: [accountID]) != nil
    }

    func readyWebsiteAccount(from accountIDs: Set<UUID>) async -> UUID? {
        for account in accounts where accountIDs.contains(account.id) {
            await checkAccount(account)
            if accountHealth[account.id]?.isReady == true { return account.id }
        }
        if !accountIDs.isEmpty {
            notice = Notice(
                title: accountIDs.count == 1 ? "This account is not ready" : "No source account is ready",
                message: "Check the account status or use Sign In Again before opening Roblox websites."
            )
        }
        return nil
    }

    func checkAccounts(_ accountIDs: Set<UUID>) async {
        let selected = accounts.filter { accountIDs.contains($0.id) }
        for account in selected { accountHealth[account.id] = .checking }
        let checker = healthChecker
        await withTaskGroup(of: (UUID, AccountHealth).self) { group in
            for account in selected {
                group.addTask { (account.id, await checker.check(account)) }
            }
            for await (accountID, health) in group { accountHealth[accountID] = health }
        }
    }

    func discoverPlayers(sourceAccounts: [ManagedAccount]) async {
        guard !isDiscoveringPlayers else { return }
        guard !sourceAccounts.isEmpty else {
            discoveredPlayers = []
            discoveryFailures = []
            discoveryUpdatedAt = Date()
            return
        }
        isDiscoveringPlayers = true
        defer { isDiscoveringPlayers = false }

        await checkAccounts(Set(sourceAccounts.map(\.id)))
        let validSources = sourceAccounts.filter { accountHealth[$0.id]?.isReady == true }
        guard !validSources.isEmpty else {
            discoveredPlayers = []
            discoveryFailures = sourceAccounts.map {
                PlayerDiscoveryFailure(accountID: $0.id, message: "Sign in to this account before checking its friends.")
            }
            discoveryUpdatedAt = Date()
            return
        }
        var sources: [PlayerDiscoverySource] = []
        var sessionFailures: [PlayerDiscoveryFailure] = []
        for account in validSources {
            do {
                guard let session = try vault.read(for: account.id), !session.isEmpty else {
                    sessionFailures.append(PlayerDiscoveryFailure(
                        accountID: account.id,
                        message: "Sign in to this account before checking its friends."
                    ))
                    continue
                }
                sources.append(PlayerDiscoverySource(account: account, session: session))
            } catch {
                sessionFailures.append(PlayerDiscoveryFailure(accountID: account.id, message: error.localizedDescription))
            }
        }
        let result = await playerDiscovery.discover(sources: sources)
        discoveredPlayers = result.players
        discoveryFailures = sessionFailures + result.failures
        discoveryUpdatedAt = result.completedAt
    }

    func continueVerification(for player: DiscoveredPlayer) async {
        let verification = await playerDiscovery.continueVerification(for: player)
        updateDiscoveredPlayer(player.id, verification: verification)
    }

    func assessments(
        for player: DiscoveredPlayer,
        accountIDs: Set<UUID>,
        refreshServer: Bool = false
    ) async -> [AccountJoinAssessment] {
        var current = player
        if refreshServer {
            current.verification = await playerDiscovery.refreshVerification(for: player)
            updateDiscoveredPlayer(player.id, verification: current.verification)
        }
        guard let placeID = current.presence.placeID,
              let jobID = current.presence.jobID,
              !jobID.isEmpty else { return [] }
        let selected = accounts.filter { accountIDs.contains($0.id) }
        await checkAccounts(Set(selected.map(\.id)))
        return await joinAssessor.assess(
            target: PlayerJoinTarget(placeID: placeID, jobID: jobID, verification: current.verification),
            accounts: selected,
            health: accountHealth,
            runningAccountIDs: runningAccountIDs
        )
    }

    func launchVerifiedPlayer(_ player: DiscoveredPlayer, accountIDs: Set<UUID>) async {
        guard let placeID = player.presence.placeID,
              let jobID = player.presence.jobID,
              !jobID.isEmpty else {
            notice = Notice(title: "No server was supplied", message: "Open the player's profile with a source account instead.")
            return
        }
        let updatedVerification = await playerDiscovery.refreshVerification(for: player)
        updateDiscoveredPlayer(player.id, verification: updatedVerification)
        guard case .verifiedPublic(let server) = updatedVerification else {
            notice = Notice(
                title: "The server is not confirmed as public",
                message: "Continue checking or open the player's profile with a source account."
            )
            return
        }
        let assessments = await assessments(
            for: playerWithVerification(player, updatedVerification),
            accountIDs: accountIDs
        )
        let expectedIDs = Set(assessments.filter { $0.state == .expectedToJoin }.map(\.accountID))
        guard !expectedIDs.isEmpty else {
            notice = Notice(title: "No accounts are ready", message: "Check the account status and server capacity.")
            return
        }
        if expectedIDs.count < accountIDs.count {
            notice = Notice(
                title: "Only \(expectedIDs.count) account\(expectedIDs.count == 1 ? "" : "s") can start",
                message: "The last server update shows \(server.openSpaces) open space\(server.openSpaces == 1 ? "" : "s"). Change the selection before launching."
            )
            return
        }
        batchSelectedIDs = expectedIDs
        await launchBatch(
            placeText: String(placeID),
            server: .publicInstance(jobID: jobID, playing: server.playing, maxPlayers: server.maxPlayers),
            skipPublicServerPreflight: true,
            skipHealthPreflight: true
        )
    }

    func launchFriendPlayer(_ player: DiscoveredPlayer, accountIDs: Set<UUID>) async {
        guard case .friendTarget = player.verification,
              let placeID = player.presence.placeID,
              let jobID = player.presence.jobID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jobID.isEmpty else {
            notice = Notice(
                title: "No friend server is available",
                message: "Refresh the friend list. Roblox may have stopped sharing this server."
            )
            return
        }

        let selected = accounts.filter { accountIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        guard selected.allSatisfy({ !runningAccountIDs.contains($0.id) }) else {
            notice = Notice(
                title: "A selected account is already running",
                message: "Clear that account or stop its managed Roblox client, then try again."
            )
            return
        }

        await checkAccounts(accountIDs)
        let notReady = selected.filter { accountHealth[$0.id]?.isReady != true }
        guard notReady.isEmpty else {
            notice = Notice(
                title: "Some accounts are not ready",
                message: "Sign in to the marked accounts. No Roblox client was started."
            )
            return
        }

        guard let source = selected.first(where: { player.candidate.sourceAccountIDs.contains($0.id) }) else {
            notice = Notice(
                title: "Select a friend account",
                message: "Select at least one account listed under Found through. That account must start first."
            )
            return
        }

        batchStatus = "Starting @\(source.username) first"
        await launch(
            account: source,
            placeText: String(placeID),
            server: .manualJob(jobID),
            rememberSelection: false
        )
        guard runningAccountIDs.contains(source.id) else {
            batchStatus = "The source account did not start"
            return
        }

        let remainingIDs = accountIDs.subtracting([source.id])
        guard !remainingIDs.isEmpty else {
            clearRememberedFriendServer(jobID, accountIDs: [source.id])
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Started @\(source.username)"
            return
        }

        batchSelectedIDs = remainingIDs
        batchStatus = "Source started. Starting \(remainingIDs.count) more"
        await launchBatch(
            placeText: String(placeID),
            server: .manualJob(jobID),
            skipPublicServerPreflight: true,
            skipHealthPreflight: true,
            rememberSelection: false
        )
        clearRememberedFriendServer(
            jobID,
            accountIDs: accountIDs.intersection(runningAccountIDs)
        )
        if accountIDs.isSubset(of: runningAccountIDs) {
            batchStatus = "Started all \(accountIDs.count) accounts"
            launchStatus = "Running \(accountIDs.count) accounts in the friend server"
        }
    }

    func tryUnconfirmedPlayer(_ player: DiscoveredPlayer, accountIDs: Set<UUID>) async {
        let canTryServer: Bool
        switch player.verification {
        case .unconfirmed, .paused: canTryServer = true
        default: canTryServer = false
        }
        guard canTryServer,
              let placeID = player.presence.placeID,
              let jobID = player.presence.jobID,
              !jobID.isEmpty else {
            notice = Notice(
                title: "This server cannot be tried",
                message: "Continue checking the public server list or open the player's profile."
            )
            return
        }

        let selected = accounts.filter { accountIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        await checkAccounts(accountIDs)

        let blocked = selected.filter {
            runningAccountIDs.contains($0.id) || accountHealth[$0.id]?.isReady != true
        }
        guard blocked.isEmpty else {
            notice = Notice(
                title: "Some accounts are not ready",
                message: "Review each account status. No account was launched."
            )
            return
        }

        batchSelectedIDs = accountIDs
        await launchBatch(
            placeText: String(placeID),
            server: .manualJob(jobID),
            skipHealthPreflight: true
        )
    }

    func sessionCookie(for accountID: UUID) throws -> String? {
        try vault.read(for: accountID)
    }

    func synchronizeWebSession(accountID: UUID, cookie rawCookie: String?) async {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        guard let rawCookie, !RobloxAPIClient.normalizedCookie(from: rawCookie).isEmpty else {
            accountHealth[accountID] = await healthChecker.check(account)
            return
        }
        do {
            let cookie = RobloxAPIClient.normalizedCookie(from: rawCookie)
            let user = try await api.authenticatedUser(cookie: cookie)
            guard user.id == account.userID else {
                accountHealth[accountID] = .wrongAccount(actualUserID: user.id)
                notice = Notice(
                    title: "The website signed in to a different account",
                    message: "The saved sign-in was not changed."
                )
                return
            }
            let current = try vault.read(for: accountID)
            if RobloxAPIClient.normalizedCookie(from: current ?? "") != cookie {
                try vault.save(cookie, for: accountID)
            }
            accountHealth[accountID] = .ready(lastChecked: Date())
        } catch RobloxAPIError.invalidSession {
            accountHealth[accountID] = .signedOut
        } catch {
            accountHealth[accountID] = .networkUnavailable
        }
    }

    func replaceSession(_ rawCookie: String, for account: ManagedAccount) async -> Bool {
        do {
            let cookie = RobloxAPIClient.normalizedCookie(from: rawCookie)
            let user = try await api.authenticatedUser(cookie: cookie)
            guard user.id == account.userID else {
                accountHealth[account.id] = .wrongAccount(actualUserID: user.id)
                notice = Notice(title: "Wrong Roblox account", message: "Sign in as @\(account.username). The saved sign-in was not changed.")
                return false
            }
            try vault.save(cookie, for: account.id)
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index].username = user.name
                accounts[index].displayName = user.displayName
                accounts[index].avatarURLString = await api.avatarURL(userID: user.id)?.absoluteString
                try repository.save(accounts)
            }
            accountHealth[account.id] = .ready(lastChecked: Date())
            return true
        } catch {
            notice = Notice(title: "Sign-in was not replaced", message: error.localizedDescription)
            return false
        }
    }

    func saveLaunchSet(_ launchSet: LaunchSet) {
        var updated = launchSet
        updated.updatedAt = Date()
        if let index = launchSets.firstIndex(where: { $0.id == launchSet.id }) {
            launchSets[index] = updated
        } else {
            launchSets.append(updated)
        }
        launchSets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        do { try launchSetRepository.save(launchSets) }
        catch { notice = Notice(title: "Launch Set was not saved", message: error.localizedDescription) }
    }

    func removeLaunchSet(_ launchSet: LaunchSet) {
        launchSets.removeAll { $0.id == launchSet.id }
        do { try launchSetRepository.save(launchSets) }
        catch { notice = Notice(title: "Launch Set was not removed", message: error.localizedDescription) }
    }

    @discardableResult
    func savePrivateServer(name rawName: String, link rawLink: String) -> SavedPrivateServer? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            notice = Notice(title: "Name required", message: "Give this private server a name that you will recognize later.")
            return nil
        }
        guard let placeID = RobloxLaunchURLBuilder.privateServerPlaceID(from: link),
              let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: link) else {
            notice = Notice(title: "Private server was not saved", message: "Paste a complete Roblox private server link.")
            return nil
        }

        let previous = privateServers
        let now = Date()
        let saved: SavedPrivateServer
        if let index = privateServers.firstIndex(where: {
            $0.placeID == placeID
                && RobloxLaunchURLBuilder.privateLinkCode(from: $0.link) == linkCode
        }) {
            privateServers[index].name = name
            privateServers[index].link = link
            privateServers[index].lastUsedAt = now
            saved = privateServers[index]
        } else {
            saved = SavedPrivateServer(
                name: name,
                placeID: placeID,
                link: link,
                lastUsedAt: now
            )
            privateServers.append(saved)
        }
        privateServers = sortedPrivateServers(privateServers)
        do {
            try privateServerRepository.save(privateServers)
            return saved
        } catch {
            privateServers = previous
            notice = Notice(title: "Private server was not saved", message: error.localizedDescription)
            return nil
        }
    }

    func markPrivateServerUsed(_ server: SavedPrivateServer) {
        guard let index = privateServers.firstIndex(where: { $0.id == server.id }) else { return }
        let previous = privateServers
        privateServers[index].lastUsedAt = Date()
        privateServers = sortedPrivateServers(privateServers)
        do { try privateServerRepository.save(privateServers) }
        catch {
            privateServers = previous
            notice = Notice(title: "Private server history was not saved", message: error.localizedDescription)
        }
    }

    func removePrivateServer(_ server: SavedPrivateServer) {
        let previous = privateServers
        privateServers.removeAll { $0.id == server.id }
        do { try privateServerRepository.save(privateServers) }
        catch {
            privateServers = previous
            notice = Notice(title: "Private server was not removed", message: error.localizedDescription)
        }
    }

    func runLaunchSet(_ launchSet: LaunchSet) async {
        let groupAccountIDs = Set(accounts.filter { account in
            launchSet.groupNames.contains { account.belongs(to: $0) }
        }.map(\.id))
        let requested = Set(launchSet.accountIDs).union(groupAccountIDs)
        batchSelectedIDs = Set(accounts.filter { requested.contains($0.id) && !isRunning($0) }.map(\.id))
        updateBatchSelectionStatus()
        guard !batchSelectedIDs.isEmpty else {
            notice = Notice(title: "No accounts are ready", message: "Every account in this Launch Set is missing or already running.")
            return
        }
        switch launchSet.serverStrategy {
        case .robloxChooses:
            await launchBatch(placeText: String(launchSet.placeID), server: .automatic)
        case .privateServerLink(let link):
            await launchBatch(placeText: String(launchSet.placeID), server: .privateLink(link))
        case .browseBeforeLaunch:
            notice = Notice(
                title: "Launch Set loaded",
                message: "The accounts are selected. Use Choose Server in the main window to browse before launch."
            )
        case .joinPlayer:
            notice = Notice(
                title: "Launch Set loaded",
                message: "The accounts are selected. Open Find Players and choose a visible player."
            )
        }
    }

    func setExperienceFavorite(_ experience: ExperienceRecord, isFavorite: Bool) {
        guard let index = experiences.firstIndex(where: { $0.placeID == experience.placeID }) else { return }
        experiences[index].isFavorite = isFavorite
        do { try experienceRepository.save(experiences) }
        catch { notice = Notice(title: "Favorite was not saved", message: error.localizedDescription) }
    }

    func exportMetadata(includePrivateLinks: Bool = false) throws -> Data {
        try archiveService.exportData(
            accounts: accounts,
            groups: groupNames,
            experiences: experiences,
            launchSets: launchSets,
            includePrivateLinks: includePrivateLinks
        )
    }

    func importMetadata(_ data: Data) throws -> Int {
        let result = try archiveService.importData(
            data,
            existingAccounts: accounts,
            existingGroups: groupNames,
            existingExperiences: experiences,
            existingLaunchSets: launchSets
        )
        try repository.save(result.accounts)
        try repository.saveGroups(result.groups)
        try experienceRepository.save(result.experiences)
        try launchSetRepository.save(result.launchSets)
        accounts = result.accounts
        groups = result.groups
        experiences = result.experiences
        launchSets = result.launchSets
        for account in accounts where accountHealth[account.id] == nil { accountHealth[account.id] = .unchecked }
        return result.importedAccountCount
    }

    private func updateDiscoveredPlayer(_ userID: Int64, verification: PublicServerVerification) {
        guard let index = discoveredPlayers.firstIndex(where: { $0.id == userID }) else { return }
        discoveredPlayers[index].verification = verification
    }

    private func playerWithVerification(
        _ player: DiscoveredPlayer,
        _ verification: PublicServerVerification
    ) -> DiscoveredPlayer {
        var copy = player
        copy.verification = verification
        return copy
    }

    func importSession(_ rawCookie: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let cookie = RobloxAPIClient.normalizedCookie(from: rawCookie)
            let user = try await api.authenticatedUser(cookie: cookie)
            let avatarURL = await api.avatarURL(userID: user.id)
            if let index = accounts.firstIndex(where: { $0.userID == user.id }) {
                try vault.save(cookie, for: accounts[index].id)
                accounts[index].username = user.name
                accounts[index].displayName = user.displayName
                accounts[index].avatarURLString = avatarURL?.absoluteString
                try repository.save(accounts)
                selectedID = accounts[index].id
                accountHealth[accounts[index].id] = .ready(lastChecked: Date())
                notice = Notice(title: "Session updated", message: "\(user.name) is ready to launch.")
            } else {
                let account = ManagedAccount(
                    userID: user.id,
                    username: user.name,
                    displayName: user.displayName
                )
                var accountWithAvatar = account
                accountWithAvatar.avatarURLString = avatarURL?.absoluteString
                try vault.save(cookie, for: accountWithAvatar.id)
                accounts.append(accountWithAvatar)
                do {
                    try repository.save(accounts)
                } catch {
                    accounts.removeAll(where: { $0.id == accountWithAvatar.id })
                    try? vault.delete(for: accountWithAvatar.id)
                    throw error
                }
                selectedID = accountWithAvatar.id
                accountHealth[accountWithAvatar.id] = .ready(lastChecked: Date())
                notice = Notice(title: "Account added", message: "\(user.name) is saved securely on this Mac.")
            }
            return true
        } catch {
            notice = Notice(title: "Account was not added", message: error.localizedDescription)
            return false
        }
    }

    func update(_ account: ManagedAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updated = account
        updated.groups = ManagedAccount.normalizedGroups(updated.groups)
        if updated.avatarURLString == nil {
            updated.avatarURLString = accounts[index].avatarURLString
        }
        accounts[index] = updated
        groups = ManagedAccount.normalizedGroups(groups + updated.groups)
        do {
            try repository.save(accounts)
            try repository.saveGroups(groups)
            launchStatus = "Saved"
        } catch {
            notice = Notice(title: "Changes were not saved", message: error.localizedDescription)
        }
    }

    func remove(_ account: ManagedAccount) {
        guard !isRunning(account) else {
            notice = Notice(title: "Account is still running", message: "Stop this account's Roblox instance before removing it.")
            return
        }
        let original = accounts
        let updated = accounts.filter { $0.id != account.id }
        do {
            try repository.save(updated)
            try vault.delete(for: account.id)
            accounts = updated
            batchSelectedIDs.remove(account.id)
            batchStates[account.id] = nil
            accountHealth[account.id] = nil
            activeLaunchTargets[account.id] = nil
            selectedID = accounts.first?.id
            Task {
                await playerDiscovery.clearCache()
                await launcher.removePreparedCopy(accountID: account.id)
            }
            try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
        } catch {
            try? repository.save(original)
            notice = Notice(title: "Account was not removed", message: error.localizedDescription)
        }
    }

    func stop(_ account: ManagedAccount) async {
        guard isRunning(account), !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        launchStatus = "Stopping @\(account.username)"
        if await launcher.stop(accountID: account.id) {
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await refreshRunningInstances()
                if !isRunning(account) { break }
            }
            launchStatus = isRunning(account) ? "Roblox is still closing" : "Stopped @\(account.username)"
        } else {
            launchStatus = "Stop failed"
            notice = Notice(title: "Roblox did not stop", message: "Close this Roblox window normally, then try again.")
        }
    }

    func stopAll() async {
        let accountIDs = runningAccountIDs
        guard !accountIDs.isEmpty, !isWorking, !isBatchLaunching else { return }

        isWorking = true
        isStoppingAll = true
        launchStatus = "Stopping all Roblox clients"
        batchStatus = "Stopping all Roblox clients"
        defer {
            isWorking = false
            isStoppingAll = false
        }

        let launcher = self.launcher
        var failedAccountIDs = Set<UUID>()
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for accountID in accountIDs {
                group.addTask {
                    (accountID, await launcher.stop(accountID: accountID))
                }
            }
            for await (accountID, stopped) in group where !stopped {
                failedAccountIDs.insert(accountID)
            }
        }

        await refreshRunningInstances()
        if runningAccountIDs.isEmpty {
            launchStatus = "Stopped all Roblox clients"
            batchStatus = "All Roblox clients stopped"
        } else {
            let failedCount = max(failedAccountIDs.count, runningAccountIDs.count)
            launchStatus = "Some Roblox clients are still closing"
            batchStatus = "\(failedCount) client\(failedCount == 1 ? "" : "s") still running"
            notice = Notice(
                title: "Some Roblox clients did not stop",
                message: "Close the remaining Roblox windows normally, then try again."
            )
        }
    }

    func launch(account: ManagedAccount, placeText: String, serverText: String) async {
        await launch(
            account: account,
            placeText: placeText,
            server: RobloxServerSelection.savedValue(serverText)
        )
    }

    func launchFromWebsite(accountID: UUID, request: RobloxWebLaunchRequest) async {
        await refreshRunningInstances()
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            notice = Notice(
                title: "Account is no longer available",
                message: "Close this website window and choose another managed account."
            )
            return
        }
        await launch(
            account: account,
            placeText: String(request.placeID),
            server: request.server,
            rememberSelection: false
        )
    }

    func launch(
        account: ManagedAccount,
        placeText: String,
        server: RobloxServerSelection,
        rememberSelection: Bool = true
    ) async {
        guard !isWorking, !isBatchLaunching else {
            notice = Notice(
                title: "Another launch is starting",
                message: "Wait for the current launch to finish, then select Play again."
            )
            return
        }
        guard !isRunning(account) else {
            notice = Notice(title: "Account is already running", message: RobloxLaunchError.accountAlreadyRunning.localizedDescription)
            return
        }
        guard let placeID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines)), placeID > 0 else {
            notice = Notice(title: "Check the place ID", message: RobloxLaunchError.invalidPlaceID.localizedDescription)
            return
        }
        var launchServer = server
        if case .publicInstance(let jobID, _, _) = server {
            let verification = await verifyPublicServer(
                placeID: placeID,
                jobID: jobID,
                maximumPages: 100,
                forceRefresh: true
            )
            guard case .verifiedPublic(let current) = verification, current.openSpaces > 0 else {
                notice = Notice(
                    title: "The selected server is no longer available",
                    message: "Choose another public server or let Roblox choose."
                )
                return
            }
            launchServer = .publicInstance(jobID: current.id, playing: current.playing, maxPlayers: current.maxPlayers)
        }
        await checkAccount(account)
        guard accountHealth[account.id]?.isReady == true else {
            notice = Notice(
                title: "This account is not ready",
                message: "Use Sign In Again, then try the launch again."
            )
            return
        }
        isWorking = true
        launchStatus = "Requesting a launch ticket"
        defer { isWorking = false }

        do {
            guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                throw RobloxAPIError.invalidSession
            }
            if case .privateLink = launchServer {
                launchStatus = "Resolving the private server"
            }
            let target = try await makeServerTarget(
                launchServer,
                placeID: placeID,
                cookie: cookie,
                api: api
            )

            launchStatus = "Requesting a launch ticket"
            let ticket = try await api.authenticationTicket(cookie: cookie)
            let url = try builder.makeURL(ticket: ticket, placeID: placeID, target: target)
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Preparing a separate Roblox copy"
            case .official:
                launchStatus = "Opening official Roblox"
            case .modifiedParallel:
                launchStatus = "Preparing the advanced fallback copy"
            }
            let instance = try await launcher.launch(url, for: account.id, mode: launchMode)
            await refreshRunningInstances()
            guard isRunning(account) else {
                throw launchMode == .official
                    ? RobloxLaunchError.officialParallelUnavailable
                    : RobloxLaunchError.openFailed
            }

            var updated = account
            updated.lastUsed = Date()
            if rememberSelection {
                updated.savedPlaceID = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.savedServer = launchServer.persistedValue
            }
            update(updated)
            recordLaunchTarget(
                accountID: account.id,
                processIdentifier: instance.processIdentifier,
                placeID: placeID,
                server: launchServer
            )
            recordExperienceLaunch(placeID: placeID)
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Running @\(account.username) with the recommended method"
            case .official:
                launchStatus = "Running @\(account.username) with official Roblox"
            case .modifiedParallel:
                launchStatus = "Running @\(account.username) with the advanced fallback"
            }
        } catch {
            launchStatus = "Launch failed"
            notice = Notice(title: "Roblox did not launch", message: error.localizedDescription)
        }
    }

    func launchBatch(placeText: String, serverText: String) async {
        await launchBatch(placeText: placeText, server: RobloxServerSelection.savedValue(serverText))
    }

    func launchBatch(
        placeText: String,
        server: RobloxServerSelection,
        skipPublicServerPreflight: Bool = false,
        skipHealthPreflight: Bool = false,
        rememberSelection: Bool = true
    ) async {
        guard !isWorking, !isBatchLaunching else { return }
        guard let placeID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines)), placeID > 0 else {
            notice = Notice(title: "Check the shared place ID", message: RobloxLaunchError.invalidPlaceID.localizedDescription)
            return
        }

        let selectedAccounts = accounts.filter { batchSelectedIDs.contains($0.id) && !isRunning($0) }
        guard !selectedAccounts.isEmpty else {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Select accounts that are not running"
            return
        }

        if !skipHealthPreflight {
            await checkAccounts(Set(selectedAccounts.map(\.id)))
            let notReady = selectedAccounts.filter { accountHealth[$0.id]?.isReady != true }
            if !notReady.isEmpty {
                for account in notReady {
                    batchStates[account.id] = .failed("Sign in again before launching this account.")
                }
                batchStatus = "\(notReady.count) account\(notReady.count == 1 ? " is" : "s are") not ready"
                notice = Notice(
                    title: "Some accounts are not ready",
                    message: "Review the marked accounts. No account was launched."
                )
                return
            }
        }

        var launchServer = server
        if !skipPublicServerPreflight,
           case .publicInstance(let jobID, _, _) = server {
            let verification = await verifyPublicServer(
                placeID: placeID,
                jobID: jobID,
                maximumPages: 100,
                forceRefresh: true
            )
            guard case .verifiedPublic(let current) = verification else {
                notice = Notice(
                    title: "The selected server is no longer public",
                    message: "Choose another public server or let Roblox choose. No account was launched."
                )
                return
            }
            guard current.openSpaces >= selectedAccounts.count else {
                notice = Notice(
                    title: "The server no longer has enough space",
                    message: "It has \(current.openSpaces) open space\(current.openSpaces == 1 ? "" : "s") for \(selectedAccounts.count) selected accounts. Change the selection before launching."
                )
                return
            }
            launchServer = .publicInstance(jobID: current.id, playing: current.playing, maxPlayers: current.maxPlayers)
        }

        if case .privateLink(let link) = launchServer {
            guard RobloxLaunchURLBuilder.privateShareCode(from: link) == nil else {
                notice = Notice(
                    title: "This private link needs the Roblox website",
                    message: "Open the private link in each selected account's Roblox Website window. This app does not share one account's access code with another account."
                )
                return
            }
            guard let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: link) else {
                notice = Notice(title: "Check the private server link", message: RobloxLaunchError.invalidServer.localizedDescription)
                return
            }
            let denied = await privateAccessFailures(
                accounts: selectedAccounts,
                placeID: placeID,
                linkCode: linkCode
            )
            if !denied.isEmpty {
                let deniedIDs = Set(denied.keys)
                batchSelectedIDs.subtract(deniedIDs)
                for (accountID, message) in denied { batchStates[accountID] = .failed(message) }
                batchStatus = "\(selectedAccounts.count - denied.count) allowed, \(denied.count) denied"
                notice = Notice(
                    title: "Some accounts cannot access this private server",
                    message: "The denied accounts are marked in the sidebar. Review the selection, then launch the allowed accounts."
                )
                return
            }
        }

        let vault = self.vault
        let api = self.api
        let builder = self.builder
        let launcher = self.launcher
        let launchMode = self.launchMode
        let total = selectedAccounts.count

        isWorking = true
        isBatchLaunching = true
        batchStates = Dictionary(uniqueKeysWithValues: selectedAccounts.map { ($0.id, .starting) })
        batchStatus = "Starting 0 of \(total)"
        launchStatus = "Starting selected accounts"
        defer {
            isWorking = false
            isBatchLaunching = false
        }

        var outcomes: [BatchOutcome] = []
        await withTaskGroup(of: BatchOutcome.self) { group in
            for account in selectedAccounts {
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }

                        let target = try await makeServerTarget(
                            launchServer,
                            placeID: placeID,
                            cookie: cookie,
                            api: api
                        )

                        let ticket = try await api.authenticationTicket(cookie: cookie)
                        let url = try builder.makeURL(ticket: ticket, placeID: placeID, target: target)
                        let instance = try await launcher.launch(url, for: account.id, mode: launchMode)
                        return BatchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: instance.processIdentifier,
                            errorMessage: nil
                        )
                    } catch {
                        return BatchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: nil,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            for await outcome in group {
                outcomes.append(outcome)
                if let message = outcome.errorMessage {
                    batchStates[outcome.accountID] = .failed(message)
                } else {
                    batchStates[outcome.accountID] = nil
                }
                batchStatus = "Started \(outcomes.filter { $0.errorMessage == nil }.count) of \(total)"
            }
        }

        await refreshRunningInstances()
        outcomes = outcomes.map { outcome in
            guard outcome.errorMessage == nil,
                  !runningAccountIDs.contains(outcome.accountID) else { return outcome }
            let message = launchMode == .official
                ? RobloxLaunchError.officialParallelUnavailable.localizedDescription
                : "Roblox closed before the manager could confirm that it was running."
            batchStates[outcome.accountID] = .failed(message)
            return BatchOutcome(
                accountID: outcome.accountID,
                username: outcome.username,
                processIdentifier: outcome.processIdentifier,
                errorMessage: message
            )
        }
        for outcome in outcomes where outcome.errorMessage == nil {
            if let index = accounts.firstIndex(where: { $0.id == outcome.accountID }) {
                accounts[index].lastUsed = Date()
                if rememberSelection {
                    accounts[index].savedPlaceID = String(placeID)
                    accounts[index].savedServer = launchServer.persistedValue
                }
            }
            if let processIdentifier = outcome.processIdentifier {
                recordLaunchTarget(
                    accountID: outcome.accountID,
                    processIdentifier: processIdentifier,
                    placeID: placeID,
                    server: launchServer
                )
            }
        }
        if outcomes.contains(where: { $0.errorMessage == nil }) { recordExperienceLaunch(placeID: placeID) }
        do {
            try repository.save(accounts)
        } catch {
            notice = Notice(title: "Launch settings were not saved", message: error.localizedDescription)
        }

        let failures = outcomes.filter { $0.errorMessage != nil }
        if failures.isEmpty {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Started all \(total) accounts"
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Running \(total) accounts with the recommended method"
            case .official:
                launchStatus = "Running \(total) accounts with official Roblox"
            case .modifiedParallel:
                launchStatus = "Running \(total) accounts with the advanced fallback"
            }
        } else {
            batchSelectedIDs = Set(failures.map(\.accountID))
            batchStates = batchStates.filter { batchSelectedIDs.contains($0.key) }
            batchStatus = "\(total - failures.count) started, \(failures.count) failed"
            launchStatus = "\(total - failures.count) running, \(failures.count) failed"
            notice = Notice(
                title: "\(failures.count) account\(failures.count == 1 ? "" : "s") did not start",
                message: batchFailureMessage(failures)
            )
        }
    }

    private func updateBatchSelectionStatus() {
        let count = batchSelectedIDs.count
        batchStatus = count == 0
            ? "Select accounts from the shelf"
            : "\(count) account\(count == 1 ? "" : "s") ready"
    }

    private func clearRememberedFriendServer(_ jobID: String, accountIDs: Set<UUID>) {
        let cleanJobID = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanJobID.isEmpty else { return }

        var changed = false
        for index in accounts.indices where accountIDs.contains(accounts[index].id) {
            let savedServer = accounts[index].savedServer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard savedServer.caseInsensitiveCompare(cleanJobID) == .orderedSame else { continue }
            accounts[index].savedServer = ""
            changed = true
        }
        guard changed else { return }

        do {
            try repository.save(accounts)
        } catch {
            notice = Notice(
                title: "Launch choice was not reset",
                message: "The friend server was temporary, but the app could not reset the main launch form. Choose Automatic before your next launch."
            )
        }
    }

    private func recordLaunchTarget(
        accountID: UUID,
        processIdentifier: Int32,
        placeID: Int64,
        server: RobloxServerSelection
    ) {
        let kind: ActiveLaunchTargetKind
        let jobID: String?
        let privateReference: String?
        switch server {
        case .automatic:
            kind = .automatic
            jobID = nil
            privateReference = nil
        case .publicInstance(let value, _, _):
            kind = .verifiedPublicJob
            jobID = value
            privateReference = nil
        case .player(_, _, let value), .manualJob(let value):
            kind = .publicJob
            jobID = value
            privateReference = nil
        case .privateLink(let link):
            kind = .privateServer
            jobID = nil
            privateReference = link
        }
        activeLaunchTargets[accountID] = ActiveLaunchTargetRecord(
            accountID: accountID,
            processIdentifier: processIdentifier,
            placeID: placeID,
            targetKind: kind,
            jobID: jobID,
            privateServerReference: privateReference
        )
        try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
    }

    private func privateAccessFailures(
        accounts: [ManagedAccount],
        placeID: Int64,
        linkCode: String
    ) async -> [UUID: String] {
        let vault = self.vault
        let api = self.api
        var failures: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, String?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }
                        _ = try await api.privateServerAccessCode(
                            placeID: placeID,
                            linkCode: linkCode,
                            cookie: cookie
                        )
                        return (account.id, nil)
                    } catch {
                        return (account.id, error.localizedDescription)
                    }
                }
            }
            for await (accountID, message) in group {
                if let message { failures[accountID] = message }
            }
        }
        return failures
    }

    private func recordExperienceLaunch(placeID: Int64) {
        experiences = experienceLibrary.recordingLaunch(placeID: placeID, in: experiences)
        try? experienceRepository.save(experiences)
    }

    private func migrateExistingPrivateServers() {
        var known = Set(privateServers.compactMap { privateServerKey(placeID: $0.placeID, link: $0.link) })
        var migrated = privateServers

        for account in accounts {
            let link = account.savedServer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let placeID = RobloxLaunchURLBuilder.privateServerPlaceID(from: link),
                  let key = privateServerKey(placeID: placeID, link: link),
                  known.insert(key).inserted else { continue }
            migrated.append(SavedPrivateServer(
                name: "Private server for \(account.title)",
                placeID: placeID,
                link: link
            ))
        }

        for launchSet in launchSets {
            guard case .privateServerLink(let rawLink) = launchSet.serverStrategy else { continue }
            let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let placeID = RobloxLaunchURLBuilder.privateServerPlaceID(from: link),
                  let key = privateServerKey(placeID: placeID, link: link),
                  known.insert(key).inserted else { continue }
            migrated.append(SavedPrivateServer(
                name: "\(launchSet.name) private server",
                placeID: placeID,
                link: link
            ))
        }

        guard migrated.count != privateServers.count else { return }
        privateServers = sortedPrivateServers(migrated)
        do { try privateServerRepository.save(privateServers) }
        catch { notice = Notice(title: "Private server list could not be prepared", message: error.localizedDescription) }
    }

    private func privateServerKey(placeID: Int64, link: String) -> String? {
        guard let code = RobloxLaunchURLBuilder.privateLinkCode(from: link) else { return nil }
        return "\(placeID)|\(code)"
    }

    private func sortedPrivateServers(_ servers: [SavedPrivateServer]) -> [SavedPrivateServer] {
        servers.sorted { first, second in
            switch (first.lastUsedAt, second.lastUsedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return first.createdAt < second.createdAt
            }
        }
    }

    private func batchFailureMessage(_ failures: [BatchOutcome]) -> String {
        let shown = failures.prefix(5).map { "@\($0.username): \($0.errorMessage ?? "Unknown error")" }
        let remaining = failures.count - shown.count
        if remaining > 0 {
            return (shown + ["\(remaining) more failed."]).joined(separator: "\n")
        }
        return shown.joined(separator: "\n")
    }
}

private func makeServerTarget(
    _ selection: RobloxServerSelection,
    placeID: Int64,
    cookie: String,
    api: any RobloxAPIProviding
) async throws -> RobloxServerTarget {
    switch selection {
    case .automatic:
        return .publicServer
    case .publicInstance(let jobID, _, _), .player(_, _, let jobID), .manualJob(let jobID):
        let clean = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: clean) != nil else { throw RobloxLaunchError.invalidServer }
        return .job(clean)
    case .privateLink(let link):
        if RobloxLaunchURLBuilder.privateShareCode(from: link) != nil {
            throw RobloxLaunchError.unsupportedPrivateServerLink
        }
        guard let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: link) else {
            throw RobloxLaunchError.invalidServer
        }
        let accessCode = try await api.privateServerAccessCode(
            placeID: placeID,
            linkCode: linkCode,
            cookie: cookie
        )
        return .privateServer(accessCode: accessCode, linkCode: linkCode)
    }
}

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
    private static let privateServerReferencePrefix = "keychain:private-server:"
    private static let launchSettingsDefaultsKey = "robloxLaunchSettings.v1"

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

    enum FriendRelayState: Equatable {
        case waiting
        case planning
        case starting(String)
        case confirming
        case joined(String?)
        case tryingDirect
        case failed(String)

        var label: String {
            switch self {
            case .waiting: return "Waiting"
            case .planning: return "Finding a friend path"
            case .starting(let username): return "Joining @\(username)"
            case .confirming: return "Checking server"
            case .joined(let username):
                return username.map { "Joined through @\($0)" } ?? "Joined friend"
            case .tryingDirect: return "Trying server directly"
            case .failed: return "Could not join"
            }
        }

        var detail: String? {
            guard case .failed(let message) = self else { return nil }
            return message
        }
    }

    private struct LaunchOutcome: Sendable {
        let accountID: UUID
        let username: String
        let processIdentifier: Int32?
        let placeID: Int64?
        let errorMessage: String?
        let placementResult: WindowPlacementResult?
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
    @Published private(set) var isOpeningSelectedApps = false
    @Published var batchWindowArrangement: WindowArrangementPolicy = .savedPlacements
    @Published var batchLaunchSettingsOverride: RobloxLaunchSettings? = nil
    @Published private(set) var appOpeningAccountIDs = Set<UUID>()
    @Published private(set) var isStoppingAll = false
    @Published private(set) var batchStatus = "Select accounts from the shelf"
    @Published private(set) var launchMode: RobloxLaunchMode
    @Published var launchSettings: RobloxLaunchSettings {
        didSet {
            if let data = try? JSONEncoder().encode(launchSettings) {
                settingsDefaults.set(data, forKey: Self.launchSettingsDefaultsKey)
            }
        }
    }
    @Published private(set) var groups: [String] = []
    @Published private(set) var discoveredPlayers: [DiscoveredPlayer] = []
    @Published private(set) var discoveryFailures: [PlayerDiscoveryFailure] = []
    @Published private(set) var discoveryUpdatedAt: Date?
    @Published private(set) var isDiscoveringPlayers = false
    @Published private(set) var isFriendRelayLaunching = false
    @Published private(set) var friendRelayPlayerID: Int64?
    @Published private(set) var friendRelayStates: [UUID: FriendRelayState] = [:]
    @Published private(set) var accountHealth: [UUID: AccountHealth] = [:]
    @Published private(set) var launchSets: [LaunchSet] = []
    @Published private(set) var runningLaunchSetID: UUID?
    @Published private(set) var experiences: [ExperienceRecord] = []
    @Published private(set) var experienceMetadataLoadingIDs = Set<Int64>()
    @Published private(set) var privateServers: [SavedPrivateServer] = []
    @Published private(set) var activeLaunchTargets: [UUID: ActiveLaunchTargetRecord] = [:]

    let windowLayout: WindowLayoutController

    private let repository: AccountRepository
    private let vault: any SecretVault
    private let profileNoteVault: any ProfileNoteVault
    private let api: any RobloxAPIProviding
    private let builder: RobloxLaunchURLBuilder
    private let launcher: any ParallelRobloxLaunching
    private let playerDiscovery: PlayerDiscoveryService
    private let friendRelay: any FriendRelayProviding
    private let joinAssessor: JoinAssessmentService
    private let healthChecker: any AccountHealthChecking
    private let launchSetRepository: LaunchSetRepository
    private let experienceRepository: ExperienceLibraryRepository
    private let experienceMetadataProvider: any ExperienceMetadataProviding
    private let privateServerRepository: PrivateServerRepository
    private let activeLaunchRepository: ActiveLaunchTargetRepository
    private let settingsDefaults: UserDefaults
    private let archiveService = MetadataArchiveService()
    private var serverPageCache: [String: PublicServerSnapshot] = [:]
    private let serverCacheLifetime: TimeInterval = 60
    private var didStartInitialAccountCheck = false
    private var friendRelayCancellationRequested = false

    init(
        repository: AccountRepository = AccountRepository(),
        vault: any SecretVault = KeychainVault(),
        profileNoteVault: (any ProfileNoteVault)? = nil,
        api: any RobloxAPIProviding = RobloxAPIClient(),
        builder: RobloxLaunchURLBuilder = RobloxLaunchURLBuilder(),
        launcher: (any ParallelRobloxLaunching)? = nil,
        launchMode: RobloxLaunchMode? = nil,
        playerDiscovery: PlayerDiscoveryService? = nil,
        friendRelay: (any FriendRelayProviding)? = nil,
        joinAssessor: JoinAssessmentService? = nil,
        healthChecker: (any AccountHealthChecking)? = nil,
        launchSetRepository: LaunchSetRepository? = nil,
        experienceRepository: ExperienceLibraryRepository? = nil,
        experienceMetadataProvider: (any ExperienceMetadataProviding)? = nil,
        privateServerRepository: PrivateServerRepository? = nil,
        activeLaunchRepository: ActiveLaunchTargetRepository? = nil,
        windowLayout: WindowLayoutController? = nil,
        settingsDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.vault = vault
        self.profileNoteVault = profileNoteVault
            ?? (vault as? any ProfileNoteVault)
            ?? KeychainProfileNoteVault()
        self.api = api
        self.builder = builder
        self.launcher = launcher ?? ParallelRobloxLauncher()
        self.playerDiscovery = playerDiscovery ?? PlayerDiscoveryService(
            social: RobloxSocialAPIClient()
        )
        self.friendRelay = friendRelay ?? FriendRelayService()
        self.joinAssessor = joinAssessor ?? JoinAssessmentService()
        self.healthChecker = healthChecker ?? AccountHealthService(vault: vault, api: api)
        self.launchSetRepository = launchSetRepository ?? LaunchSetRepository(
            fileName: "LaunchSets.json",
            dataDirectory: repository.dataDirectory
        )
        self.experienceRepository = experienceRepository ?? ExperienceLibraryRepository(
            fileName: "Experiences.json",
            dataDirectory: repository.dataDirectory
        )
        self.experienceMetadataProvider = experienceMetadataProvider ?? RobloxExperienceMetadataClient()
        self.privateServerRepository = privateServerRepository ?? PrivateServerRepository(
            fileName: "PrivateServers.json",
            dataDirectory: repository.dataDirectory
        )
        self.activeLaunchRepository = activeLaunchRepository ?? ActiveLaunchTargetRepository(
            fileName: "ActiveLaunches.json",
            dataDirectory: repository.dataDirectory
        )
        self.settingsDefaults = settingsDefaults
        self.launchSettings = settingsDefaults.data(forKey: Self.launchSettingsDefaultsKey)
            .flatMap { try? JSONDecoder().decode(RobloxLaunchSettings.self, from: $0) }
            ?? .unchanged
        self.windowLayout = windowLayout ?? WindowLayoutController()
        self.launchMode = launchMode == .modifiedParallel ? .modifiedParallel : .unmodifiedParallel
        load()
        self.windowLayout.removeAssignmentsForMissingAccounts(validAccountIDs: Set(accounts.map(\.id)))
    }

    func setLaunchMode(_ mode: RobloxLaunchMode) {
        guard !isWorking, !isBatchLaunching, appOpeningAccountIDs.isEmpty else { return }
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
            var storageWarnings: [String] = []
            accounts = try repository.load()
            var metadataNeedsSave = try loadSecureProfileNotes()
            groups = ManagedAccount.normalizedGroups(
                (try repository.loadGroups()) + accounts.flatMap(\.groups)
            )
            launchSets = loadStoredRecords(
                from: launchSetRepository,
                name: "Launch Sets",
                warnings: &storageWarnings
            )
            experiences = loadStoredRecords(
                from: experienceRepository,
                name: "Recent games",
                warnings: &storageWarnings
            )
            privateServers = sortedPrivateServers(loadStoredRecords(
                from: privateServerRepository,
                name: "Private servers",
                warnings: &storageWarnings
            ))
            try loadPrivateServerCapabilities()
            for index in accounts.indices {
                guard case .manualJob = RobloxServerSelection.savedValue(accounts[index].savedServer) else {
                    continue
                }
                guard !accounts[index].savedServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                accounts[index].savedServer = ""
                metadataNeedsSave = true
            }
            if metadataNeedsSave {
                try saveAccounts(accounts)
            }
            activeLaunchTargets = Dictionary(
                loadStoredRecords(
                    from: activeLaunchRepository,
                    name: "Active launch records",
                    warnings: &storageWarnings
                ).map { ($0.accountID, $0) }
            ) { current, _ in current }
            if !storageWarnings.isEmpty {
                notice = Notice(
                    title: "Some saved data needed recovery",
                    message: storageWarnings.joined(separator: "\n\n")
                )
            }
            migrateExistingPrivateServers()
            accountHealth = Dictionary(accounts.map { ($0.id, AccountHealth.unchecked) }) { current, _ in current }
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

    private func loadStoredRecords<Record: Codable & Sendable>(
        from repository: JSONFileRepository<Record>,
        name: String,
        warnings: inout [String]
    ) -> [Record] {
        do {
            let result = try repository.loadWithRecovery()
            if result.recoveredFromBackup {
                warnings.append("\(name) was recovered from its last valid backup.")
            }
            return result.records
        } catch {
            warnings.append("\(name) could not load. \(error.localizedDescription)")
            return []
        }
    }

    private func loadPrivateServerCapabilities() throws {
        let storedValues = accounts.map(\.savedServer)
            + launchSets.compactMap {
                guard case .privateServerLink(let link) = $0.serverStrategy else { return nil }
                return link
            }
            + privateServers.map(\.link)
        guard storedValues.contains(where: {
            privateServerCapabilityKey(from: $0) != nil || isPrivateServerLink($0)
        }) else { return }

        var capabilities = try vault.readPrivateServerCapabilities()
        var migrated = false

        for index in accounts.indices {
            let key = privateServerCapabilityKey(kind: "account", id: accounts[index].id)
            let value = accounts[index].savedServer
            if privateServerCapabilityKey(from: value) != nil {
                accounts[index].savedServer = capabilities[key] ?? ""
            } else if isPrivateServerLink(value) {
                capabilities[key] = value
                migrated = true
            }
        }
        for index in launchSets.indices {
            guard case .privateServerLink(let value) = launchSets[index].serverStrategy else { continue }
            let key = privateServerCapabilityKey(kind: "launch-set", id: launchSets[index].id)
            if privateServerCapabilityKey(from: value) != nil {
                launchSets[index].serverStrategy = capabilities[key].map(ServerStrategy.privateServerLink)
                    ?? .robloxChooses
            } else if isPrivateServerLink(value) {
                capabilities[key] = value
                migrated = true
            }
        }
        for index in privateServers.indices {
            let key = privateServerCapabilityKey(kind: "library", id: privateServers[index].id)
            let value = privateServers[index].link
            if privateServerCapabilityKey(from: value) != nil {
                privateServers[index].link = capabilities[key] ?? ""
            } else if isPrivateServerLink(value) {
                capabilities[key] = value
                migrated = true
            }
        }

        guard migrated else { return }
        try vault.savePrivateServerCapabilities(capabilities)
        for _ in 0..<2 {
            try repository.save(redactedAccounts(accounts))
            try launchSetRepository.save(redactedLaunchSets(launchSets))
            try privateServerRepository.save(redactedPrivateServers(privateServers))
        }
    }

    private func saveAccounts(_ records: [ManagedAccount]) throws {
        try savePrivateServerCapabilities(accounts: records, launchSets: launchSets, privateServers: privateServers)
        try repository.save(redactedAccounts(records))
    }

    private func saveLaunchSets(_ records: [LaunchSet]) throws {
        try savePrivateServerCapabilities(accounts: accounts, launchSets: records, privateServers: privateServers)
        try launchSetRepository.save(redactedLaunchSets(records))
    }

    private func savePrivateServers(_ records: [SavedPrivateServer]) throws {
        try savePrivateServerCapabilities(accounts: accounts, launchSets: launchSets, privateServers: records)
        try privateServerRepository.save(redactedPrivateServers(records))
    }

    private func savePrivateServerCapabilities(
        accounts: [ManagedAccount],
        launchSets: [LaunchSet],
        privateServers: [SavedPrivateServer]
    ) throws {
        var capabilities: [String: String] = [:]
        for account in accounts where isPrivateServerLink(account.savedServer) {
            capabilities[privateServerCapabilityKey(kind: "account", id: account.id)] = account.savedServer
        }
        for launchSet in launchSets {
            guard case .privateServerLink(let link) = launchSet.serverStrategy,
                  isPrivateServerLink(link) else { continue }
            capabilities[privateServerCapabilityKey(kind: "launch-set", id: launchSet.id)] = link
        }
        for server in privateServers where isPrivateServerLink(server.link) {
            capabilities[privateServerCapabilityKey(kind: "library", id: server.id)] = server.link
        }
        try vault.savePrivateServerCapabilities(capabilities)
    }

    private func redactedAccounts(_ records: [ManagedAccount]) -> [ManagedAccount] {
        records.map { account in
            var account = account
            if isPrivateServerLink(account.savedServer) {
                account.savedServer = privateServerReference(for: privateServerCapabilityKey(kind: "account", id: account.id))
            }
            return account
        }
    }

    private func redactedLaunchSets(_ records: [LaunchSet]) -> [LaunchSet] {
        records.map { launchSet in
            var launchSet = launchSet
            if case .privateServerLink(let link) = launchSet.serverStrategy, isPrivateServerLink(link) {
                launchSet.serverStrategy = .privateServerLink(
                    privateServerReference(for: privateServerCapabilityKey(kind: "launch-set", id: launchSet.id))
                )
            }
            return launchSet
        }
    }

    private func redactedPrivateServers(_ records: [SavedPrivateServer]) -> [SavedPrivateServer] {
        records.map { server in
            var server = server
            if isPrivateServerLink(server.link) {
                server.link = privateServerReference(for: privateServerCapabilityKey(kind: "library", id: server.id))
            }
            return server
        }
    }

    private func privateServerCapabilityKey(kind: String, id: UUID) -> String {
        "private-server:\(kind):\(id.uuidString)"
    }

    private func privateServerReference(for key: String) -> String {
        Self.privateServerReferencePrefix + key.dropFirst("private-server:".count)
    }

    private func privateServerCapabilityKey(from value: String) -> String? {
        guard value.hasPrefix(Self.privateServerReferencePrefix) else { return nil }
        return "private-server:" + value.dropFirst(Self.privateServerReferencePrefix.count)
    }

    private func isPrivateServerLink(_ value: String) -> Bool {
        RobloxLaunchURLBuilder.privateLinkCode(from: value) != nil
            || RobloxLaunchURLBuilder.privateShareCode(from: value) != nil
    }

    func isRunning(_ account: ManagedAccount) -> Bool {
        runningAccountIDs.contains(account.id)
    }

    func isOpeningApp(_ account: ManagedAccount) -> Bool {
        appOpeningAccountIDs.contains(account.id)
    }

    func isBatchSelected(_ account: ManagedAccount) -> Bool {
        batchSelectedIDs.contains(account.id)
    }

    func toggleBatchSelection(_ account: ManagedAccount) {
        guard !isBatchLaunching, !isOpeningSelectedApps, !isRunning(account), !isOpeningApp(account) else { return }
        if batchSelectedIDs.remove(account.id) == nil {
            batchSelectedIDs.insert(account.id)
        }
        batchStates[account.id] = nil
        updateBatchSelectionStatus()
    }

    func toggleBatchGroup(_ group: String) {
        guard !isBatchLaunching, !isOpeningSelectedApps else { return }
        let eligible = Set(accounts.lazy.filter {
            $0.belongs(to: group) && !self.isRunning($0) && !self.isOpeningApp($0)
        }.map(\.id))
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
        let eligible = Set(accounts.lazy.filter {
            $0.belongs(to: group) && !self.isRunning($0) && !self.isOpeningApp($0)
        }.map(\.id))
        return !eligible.isEmpty && eligible.isSubset(of: batchSelectedIDs)
    }

    func clearBatchSelection() {
        guard !isBatchLaunching, !isOpeningSelectedApps else { return }
        batchSelectedIDs.removeAll()
        batchStates.removeAll()
        batchWindowArrangement = .savedPlacements
        batchLaunchSettingsOverride = nil
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
            if accountID != nil { try saveAccounts(accounts) }
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

    func deleteGroup(_ group: String) {
        let originalGroups = groups
        let originalAccounts = accounts
        let originalLaunchSets = launchSets
        groups.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        for index in accounts.indices {
            accounts[index].groups.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        }
        for index in launchSets.indices {
            launchSets[index].groupNames.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        }
        do {
            try repository.saveGroups(groups)
            try saveAccounts(accounts)
            try saveLaunchSets(launchSets)
            launchStatus = "Deleted group \(group)"
        } catch {
            groups = originalGroups
            accounts = originalAccounts
            launchSets = originalLaunchSets
            try? repository.saveGroups(originalGroups)
            try? saveAccounts(originalAccounts)
            try? saveLaunchSets(originalLaunchSets)
            notice = Notice(title: "Group was not deleted", message: error.localizedDescription)
        }
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
           appOpeningAccountIDs.isEmpty,
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
        if changed { try? saveAccounts(accounts) }
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
                title: accountIDs.count == 1 ? "This account is not ready" : "No selected account is ready",
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

    func checkAccountsOnStartup() async {
        guard !didStartInitialAccountCheck else { return }
        didStartInitialAccountCheck = true
        await checkAccounts(Set(accounts.map(\.id)))
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
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }
        guard let placeID = player.presence.placeID,
              let jobID = player.presence.jobID,
              !jobID.isEmpty else {
            notice = Notice(title: "No server was supplied", message: "Open the player's profile with a saved account that can see this friend.")
            return
        }
        let updatedVerification = await playerDiscovery.refreshVerification(for: player)
        updateDiscoveredPlayer(player.id, verification: updatedVerification)
        guard case .verifiedPublic(let server) = updatedVerification else {
            notice = Notice(
                title: "The server is not confirmed as public",
                message: "Continue checking or open the player's profile with a saved account that can see this friend."
            )
            return
        }
        let assessments = await assessments(
            for: playerWithVerification(player, updatedVerification),
            accountIDs: accountIDs
        )
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }
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
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }
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

        isFriendRelayLaunching = true
        friendRelayCancellationRequested = false
        friendRelayPlayerID = player.id
        friendRelayStates = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, .planning) })
        defer {
            isFriendRelayLaunching = false
            friendRelayCancellationRequested = false
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

        guard selected.contains(where: { player.candidate.sourceAccountIDs.contains($0.id) }) else {
            notice = Notice(
                title: "Select a friend account",
                message: "Select at least one account listed under Visible to these accounts. Roblox gave that account the friend's server, so it must start first."
            )
            return
        }

        var sessions: [UUID: String] = [:]
        do {
            for account in selected {
                guard let session = try vault.read(for: account.id), !session.isEmpty else {
                    throw RobloxAPIError.invalidSession
                }
                sessions[account.id] = session
            }
        } catch {
            notice = Notice(title: "Some accounts are signed out", message: error.localizedDescription)
            return
        }

        batchStatus = "Finding friend paths for \(selected.count) accounts"

        let selectedIDs = Set(selected.map(\.id))
        let sourceIDs = player.candidate.sourceAccountIDs.intersection(selectedIDs)
        let plan = await friendRelay.plan(accounts: selected, sourceAccountIDs: sourceIDs)
        let accountByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        let orderByID = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element.id, $0.offset) })
        var joinedIDs = Set<UUID>()

        let orderedSources = plan.sourceAccountIDs.sorted {
            orderByID[$0, default: .max] < orderByID[$1, default: .max]
        }
        for accountID in orderedSources {
            if friendRelayCancellationRequested { break }
            guard let account = accountByID[accountID], let session = sessions[accountID] else { continue }
            if await launchAndConfirmFriendRelayAccount(
                account: account,
                session: session,
                placeID: placeID,
                jobID: jobID,
                server: .player(
                    username: player.candidate.username,
                    userID: player.candidate.userID,
                    jobID: jobID
                ),
                initialState: .starting(player.candidate.username),
                startingStatus: "Starting @\(account.username) through @\(player.candidate.username)",
                joinedThrough: nil
            ) {
                joinedIDs.insert(accountID)
            }
        }

        let reachableAccounts = selected.filter {
            !plan.sourceAccountIDs.contains($0.id) && plan.levels[$0.id] != nil
        }.sorted { left, right in
            let leftLevel = plan.levels[left.id] ?? .max
            let rightLevel = plan.levels[right.id] ?? .max
            if leftLevel != rightLevel { return leftLevel < rightLevel }
            return orderByID[left.id, default: .max] < orderByID[right.id, default: .max]
        }

        for account in reachableAccounts {
            if friendRelayCancellationRequested { break }
            guard let session = sessions[account.id],
                  let parentID = plan.availableParent(for: account.id, joinedAccountIDs: joinedIDs),
                  let parent = accountByID[parentID] else {
                let lookupMessage = plan.lookupFailures[account.id].map { " The friend list check failed: \($0)" } ?? ""
                friendRelayStates[account.id] = .failed("No confirmed friend path was available.\(lookupMessage)")
                continue
            }
            if await launchAndConfirmFriendRelayAccount(
                account: account,
                session: session,
                placeID: placeID,
                jobID: jobID,
                server: .player(username: parent.username, userID: parent.userID, jobID: jobID),
                initialState: .starting(parent.username),
                startingStatus: "Starting @\(account.username) through @\(parent.username)",
                joinedThrough: parent.username
            ) {
                joinedIDs.insert(account.id)
            }
        }

        // Keep the previous direct Job ID behavior for accounts that have no usable
        // friend path. It is a fallback only, and it must pass the same server check.
        for account in selected where !friendRelayCancellationRequested
            && !joinedIDs.contains(account.id)
            && !runningAccountIDs.contains(account.id) {
            guard let session = sessions[account.id] else { continue }
            if await launchAndConfirmFriendRelayAccount(
                account: account,
                session: session,
                placeID: placeID,
                jobID: jobID,
                server: .manualJob(jobID),
                initialState: .tryingDirect,
                startingStatus: "Trying @\(account.username) directly",
                joinedThrough: nil
            ) {
                joinedIDs.insert(account.id)
            }
        }

        clearRememberedFriendServer(jobID, accountIDs: selectedIDs.intersection(runningAccountIDs))
        let failedIDs = selectedIDs.subtracting(joinedIDs)
        if friendRelayCancellationRequested {
            for accountID in failedIDs {
                switch friendRelayStates[accountID] {
                case .joined, .failed:
                    break
                default:
                    friendRelayStates[accountID] = .failed("The friend relay stopped before this account started.")
                }
            }
        }
        batchSelectedIDs = failedIDs
        if failedIDs.isEmpty { batchLaunchSettingsOverride = nil }
        batchStates = Dictionary(uniqueKeysWithValues: failedIDs.map { accountID in
            let message = friendRelayStates[accountID]?.detail ?? "Roblox did not confirm this account in the server."
            return (accountID, .failed(message))
        })
        if friendRelayCancellationRequested {
            batchStatus = "Friend relay stopped after \(joinedIDs.count) joined"
            launchStatus = "Friend relay stopped"
            notice = Notice(
                title: "Friend relay stopped",
                message: "No more accounts will start. Accounts that already joined will stay open."
            )
        } else if failedIDs.isEmpty {
            batchStatus = "Joined all \(selected.count) accounts"
            launchStatus = "Confirmed \(selected.count) accounts in the friend server"
            notice = nil
        } else {
            batchStatus = "\(joinedIDs.count) joined, \(failedIDs.count) could not join"
            launchStatus = "Confirmed \(joinedIDs.count) of \(selected.count) accounts"
            let failedNames = selected.filter { failedIDs.contains($0.id) }.map { "@\($0.username)" }.joined(separator: ", ")
            notice = Notice(
                title: "Some accounts could not join",
                message: "\(failedNames) could not be confirmed in this server. Review each account result in Find Players."
            )
        }
    }

    private func launchAndConfirmFriendRelayAccount(
        account: ManagedAccount,
        session: String,
        placeID: Int64,
        jobID: String,
        server: RobloxServerSelection,
        initialState: FriendRelayState,
        startingStatus: String,
        joinedThrough: String?
    ) async -> Bool {
        friendRelayStates[account.id] = initialState
        batchStatus = startingStatus
        await launch(
            account: account,
            placeText: String(placeID),
            server: server,
            rememberSelection: false,
            friendRelayStep: true,
            settingsOverride: batchLaunchSettingsOverride
        )
        guard runningAccountIDs.contains(account.id) else {
            friendRelayStates[account.id] = .failed(notice?.message ?? "Roblox did not start.")
            return false
        }

        friendRelayStates[account.id] = .confirming
        let arrival = await friendRelay.waitForServer(
            account: account,
            session: session,
            placeID: placeID,
            jobID: jobID
        )
        guard arrival == .arrived else {
            let message = friendRelayFailureMessage(for: arrival)
            friendRelayStates[account.id] = .failed(
                await stopUnconfirmedFriendRelayClient(account, failureMessage: message)
            )
            return false
        }

        friendRelayStates[account.id] = .joined(joinedThrough)
        return true
    }

    func clearFriendRelayProgress() {
        guard !isFriendRelayLaunching else { return }
        friendRelayPlayerID = nil
        friendRelayStates.removeAll()
    }

    func cancelFriendRelay() {
        guard isFriendRelayLaunching else { return }
        friendRelayCancellationRequested = true
        batchStatus = "Stopping friend relay"
    }

    private func friendRelayFailureMessage(for arrival: FriendRelayArrival) -> String {
        switch arrival {
        case .arrived:
            return ""
        case .timedOut:
            return "Roblox opened, but this account did not reach the server within 15 seconds. The server may be full, restricted, or changed."
        case .unavailable(let message):
            return "Roblox started, but the server check failed. \(message)"
        }
    }

    private func stopUnconfirmedFriendRelayClient(
        _ account: ManagedAccount,
        failureMessage: String
    ) async -> String {
        _ = await launcher.stop(accountID: account.id)
        await refreshRunningInstances()
        guard runningAccountIDs.contains(account.id) else {
            return "\(failureMessage) The unconfirmed Roblox window was closed."
        }
        return "\(failureMessage) Close the unexpected Roblox window before trying this account again."
    }

    func tryUnconfirmedPlayer(_ player: DiscoveredPlayer, accountIDs: Set<UUID>) async {
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }
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
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }

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
                try saveAccounts(accounts)
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
        do { try saveLaunchSets(launchSets) }
        catch { notice = Notice(title: "Launch Set was not saved", message: error.localizedDescription) }
    }

    func removeLaunchSet(_ launchSet: LaunchSet) {
        launchSets.removeAll { $0.id == launchSet.id }
        do { try saveLaunchSets(launchSets) }
        catch { notice = Notice(title: "Launch Set was not removed", message: error.localizedDescription) }
    }

    @discardableResult
    func savePrivateServer(name rawName: String, link rawLink: String) async -> SavedPrivateServer? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            notice = Notice(title: "Name required", message: "Give this private server a name that you will recognize later.")
            return nil
        }

        let placeID: Int64
        if let legacyPlaceID = RobloxLaunchURLBuilder.privateServerPlaceID(from: link),
           RobloxLaunchURLBuilder.privateLinkCode(from: link) != nil {
            placeID = legacyPlaceID
        } else if let shareCode = RobloxLaunchURLBuilder.privateShareCode(from: link) {
            var resolution: RobloxPrivateShareLinkResolution?
            var lastError: Error?
            for account in accounts {
                do {
                    guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else { continue }
                    resolution = try await api.privateShareLinkResolution(
                        shareCode: shareCode,
                        cookie: cookie
                    )
                    break
                } catch {
                    lastError = error
                }
            }
            guard let resolution else {
                let message = lastError?.localizedDescription
                    ?? "Add or sign in to an account, then try this link again. Roblox must check the link through a saved account."
                notice = Notice(title: "Private server was not saved", message: message)
                return nil
            }
            placeID = resolution.placeID
        } else {
            notice = Notice(title: "Private server was not saved", message: "Paste a complete Roblox private server link.")
            return nil
        }

        let previous = privateServers
        let now = Date()
        let saved: SavedPrivateServer
        let key = privateServerKey(placeID: placeID, link: link)
        if let index = privateServers.firstIndex(where: {
            privateServerKey(placeID: $0.placeID, link: $0.link) == key
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
            try savePrivateServers(privateServers)
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
        do { try savePrivateServers(privateServers) }
        catch {
            privateServers = previous
            notice = Notice(title: "Private server history was not saved", message: error.localizedDescription)
        }
    }

    func removePrivateServer(_ server: SavedPrivateServer) {
        let previous = privateServers
        privateServers.removeAll { $0.id == server.id }
        do { try savePrivateServers(privateServers) }
        catch {
            privateServers = previous
            notice = Notice(title: "Private server was not removed", message: error.localizedDescription)
        }
    }

    func runLaunchSet(_ launchSet: LaunchSet) async {
        guard runningLaunchSetID == nil,
              !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps else { return }
        runningLaunchSetID = launchSet.id
        defer { runningLaunchSetID = nil }

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
        batchWindowArrangement = launchSet.windowArrangement
        batchLaunchSettingsOverride = launchSet.launchSettings
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

    func refreshExperienceMetadata(placeIDs: Set<Int64>? = nil, force: Bool = false) async {
        let candidates = experiences.filter { experience in
            (placeIDs == nil || placeIDs?.contains(experience.placeID) == true)
                && !experienceMetadataLoadingIDs.contains(experience.placeID)
                && (force || experience.experienceName == nil || experience.thumbnailURLString == nil)
        }
        guard !candidates.isEmpty else { return }

        let candidateIDs = Set(candidates.map(\.placeID))
        experienceMetadataLoadingIDs.formUnion(candidateIDs)
        defer { experienceMetadataLoadingIDs.subtract(candidateIDs) }

        let provider = experienceMetadataProvider
        var resolved: [ExperienceMetadata] = []
        for experience in candidates {
            if let metadata = try? await provider.metadata(placeID: experience.placeID) {
                resolved.append(metadata)
            }
        }

        var changed = false
        for metadata in resolved {
            guard let index = experiences.firstIndex(where: { $0.placeID == metadata.placeID }) else { continue }
            if experiences[index].experienceName != metadata.name {
                experiences[index].experienceName = metadata.name
                changed = true
            }
            if let thumbnail = metadata.thumbnailURLString,
               experiences[index].thumbnailURLString != thumbnail {
                experiences[index].thumbnailURLString = thumbnail
                changed = true
            }
        }
        if changed { try? experienceRepository.save(experiences) }
    }

    func findExperience(placeID: Int64) async throws -> ExperienceRecord {
        if let saved = experiences.first(where: {
            $0.placeID == placeID
                && $0.experienceName != nil
                && $0.thumbnailURLString != nil
        }) {
            return saved
        }
        let metadata = try await experienceMetadataProvider.metadata(placeID: placeID)
        return ExperienceRecord(
            placeID: metadata.placeID,
            experienceName: metadata.name,
            thumbnailURLString: metadata.thumbnailURLString
        )
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
        for account in result.accounts where !account.notes.isEmpty {
            try profileNoteVault.saveNote(account.notes, for: account.id)
        }
        try savePrivateServerCapabilities(
            accounts: result.accounts,
            launchSets: result.launchSets,
            privateServers: privateServers
        )
        try repository.save(redactedAccounts(result.accounts))
        try repository.saveGroups(result.groups)
        try experienceRepository.save(result.experiences)
        try launchSetRepository.save(redactedLaunchSets(result.launchSets))
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
                try saveAccounts(accounts)
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
                    try saveAccounts(accounts)
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
        let previous = accounts[index]
        var updated = account
        updated.groups = ManagedAccount.normalizedGroups(updated.groups)
        if updated.avatarURLString == nil {
            updated.avatarURLString = accounts[index].avatarURLString
        }
        var updatedAccounts = accounts
        updatedAccounts[index] = updated
        let updatedGroups = ManagedAccount.normalizedGroups(groups + updated.groups)
        do {
            try saveSecureProfileNote(updated.notes, for: updated.id)
            try saveAccounts(updatedAccounts)
            try repository.saveGroups(updatedGroups)
            accounts = updatedAccounts
            groups = updatedGroups
            launchStatus = "Saved"
        } catch {
            try? saveSecureProfileNote(previous.notes, for: previous.id)
            notice = Notice(title: "Changes were not saved", message: error.localizedDescription)
        }
    }

    func remove(_ account: ManagedAccount) {
        guard !isRunning(account), !isOpeningApp(account) else {
            notice = Notice(title: "Account is still active", message: "Wait for this account to finish opening or stop its Roblox instance before removing it.")
            return
        }
        let original = accounts
        let updated = accounts.filter { $0.id != account.id }
        do {
            try profileNoteVault.deleteNote(for: account.id)
            try saveAccounts(updated)
            try vault.delete(for: account.id)
            accounts = updated
            batchSelectedIDs.remove(account.id)
            batchStates[account.id] = nil
            accountHealth[account.id] = nil
            activeLaunchTargets[account.id] = nil
            windowLayout.clear(accountID: account.id)
            selectedID = accounts.first?.id
            Task {
                await playerDiscovery.clearCache()
                await launcher.removePreparedCopy(accountID: account.id)
            }
            try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
        } catch {
            try? saveSecureProfileNote(account.notes, for: account.id)
            try? saveAccounts(original)
            notice = Notice(title: "Account was not removed", message: error.localizedDescription)
        }
    }

    private func loadSecureProfileNotes() throws -> Bool {
        var removedPlainTextNote = false
        for index in accounts.indices {
            let legacyNote = accounts[index].notes
            if let savedNote = try profileNoteVault.readNote(for: accounts[index].id) {
                accounts[index].notes = savedNote
            } else if !legacyNote.isEmpty {
                try profileNoteVault.saveNote(legacyNote, for: accounts[index].id)
            }
            if !legacyNote.isEmpty { removedPlainTextNote = true }
        }
        return removedPlainTextNote
    }

    private func saveSecureProfileNote(_ note: String, for accountID: UUID) throws {
        if note.isEmpty {
            try profileNoteVault.deleteNote(for: accountID)
        } else {
            try profileNoteVault.saveNote(note, for: accountID)
        }
    }

    func stop(_ account: ManagedAccount) async {
        guard isRunning(account), !isWorking, appOpeningAccountIDs.isEmpty else { return }
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
        guard !accountIDs.isEmpty, !isWorking, !isBatchLaunching, appOpeningAccountIDs.isEmpty else { return }

        isWorking = true
        isStoppingAll = true
        launchStatus = "Stopping all Roblox clients"
        batchStatus = "Stopping all Roblox clients"
        defer {
            isWorking = false
            isStoppingAll = false
        }

        let stoppedAccountIDs = await launcher.stop(accountIDs: Array(accountIDs))
        let failedAccountIDs = accountIDs.subtracting(stoppedAccountIDs)

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

    func launchApp(account: ManagedAccount) async {
        guard !isWorking, !isBatchLaunching, !isFriendRelayLaunching, !isOpeningSelectedApps else {
            notice = Notice(
                title: "Another launch is starting",
                message: "Wait for the current launch to finish, then open the Roblox app again."
            )
            return
        }
        guard !isRunning(account), !isOpeningApp(account) else {
            notice = Notice(
                title: "Account is already running",
                message: RobloxLaunchError.accountAlreadyRunning.localizedDescription
            )
            return
        }

        appOpeningAccountIDs.insert(account.id)
        launchStatus = "Opening Roblox as @\(account.username)"
        defer { appOpeningAccountIDs.remove(account.id) }

        await checkAccount(account)
        guard accountHealth[account.id]?.isReady == true else {
            notice = Notice(
                title: "This account is not ready",
                message: "Use Sign In Again, then try to open the Roblox app again."
            )
            return
        }

        do {
            guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                throw RobloxAPIError.invalidSession
            }
            let ticket = try await api.authenticationTicket(cookie: cookie)
            let url = try builder.makeAppURL(ticket: ticket)
            let instance = try await launcher.launch(
                url,
                for: account.id,
                mode: launchMode,
                settings: launchSettings
            )

            var updated = account
            updated.lastUsed = Date()
            update(updated)
            activeLaunchTargets[account.id] = nil
            try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
            await refreshRunningInstances()

            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Roblox is open as @\(account.username)"
            case .official:
                launchStatus = "Official Roblox is open as @\(account.username)"
            case .modifiedParallel:
                launchStatus = "Fallback Roblox is open as @\(account.username)"
            }
            if !runningAccountIDs.contains(account.id) {
                runningAccountIDs.insert(account.id)
            }
            await applyWindowPlacement(accountID: account.id, processIdentifier: instance.processIdentifier)
        } catch {
            launchStatus = "Open failed"
            notice = Notice(title: "Roblox did not open", message: error.localizedDescription)
        }
    }

    func launchSelectedApps(skipHealthPreflight: Bool = false) async {
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              !isOpeningSelectedApps,
              appOpeningAccountIDs.isEmpty else { return }
        let selectedAccounts = accounts.filter {
            batchSelectedIDs.contains($0.id) && !isRunning($0) && !isOpeningApp($0)
        }
        guard !selectedAccounts.isEmpty else {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Select accounts that are not running"
            return
        }
        let selectedIDs = Set(selectedAccounts.map(\.id))
        let total = selectedAccounts.count
        let windowArrangement = batchWindowArrangement
        isOpeningSelectedApps = true
        appOpeningAccountIDs.formUnion(selectedIDs)
        batchStates = Dictionary(uniqueKeysWithValues: selectedAccounts.map { ($0.id, .starting) })
        batchStatus = "Opening 0 of \(total) apps"
        launchStatus = "Opening selected Roblox apps"
        defer {
            appOpeningAccountIDs.subtract(selectedIDs)
            isOpeningSelectedApps = false
        }

        if !skipHealthPreflight {
            await checkAccounts(selectedIDs)
        }

        let readyAccounts = selectedAccounts.filter {
            skipHealthPreflight || accountHealth[$0.id]?.isReady == true
        }
        var outcomes = selectedAccounts.compactMap { account -> LaunchOutcome? in
            guard !readyAccounts.contains(where: { $0.id == account.id }) else { return nil }
            let message = "Sign in again before opening this account."
            batchStates[account.id] = .failed(message)
            return LaunchOutcome(
                accountID: account.id,
                username: account.username,
                processIdentifier: nil,
                placeID: nil,
                errorMessage: message,
                placementResult: nil
            )
        }

        let vault = self.vault
        let api = self.api
        let builder = self.builder
        let launcher = self.launcher
        let launchMode = self.launchMode
        let launchSettings = batchLaunchSettingsOverride ?? self.launchSettings
        let windowLayout = self.windowLayout
        await withTaskGroup(of: LaunchOutcome.self) { group in
            for account in readyAccounts {
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }
                        let ticket = try await api.authenticationTicket(cookie: cookie)
                        let url = try builder.makeAppURL(ticket: ticket)
                        let instance = try await launcher.launch(
                            url,
                            for: account.id,
                            mode: launchMode,
                            settings: launchSettings
                        )
                        let placementResult = await windowLayout.placeWindow(
                            accountID: account.id,
                            processIdentifier: instance.processIdentifier,
                            arrangement: windowArrangement
                        )
                        return LaunchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: instance.processIdentifier,
                            placeID: nil,
                            errorMessage: nil,
                            placementResult: placementResult
                        )
                    } catch {
                        return LaunchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: nil,
                            placeID: nil,
                            errorMessage: error.localizedDescription,
                            placementResult: nil
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
                let started = outcomes.filter { $0.errorMessage == nil }.count
                batchStatus = "Opened \(started) of \(total) apps"
            }
        }

        await refreshRunningInstances()
        outcomes = outcomes.map { outcome in
            guard outcome.errorMessage == nil,
                  !runningAccountIDs.contains(outcome.accountID) else { return outcome }
            let message = "Roblox closed before the manager could confirm that it was running."
            batchStates[outcome.accountID] = .failed(message)
            return LaunchOutcome(
                accountID: outcome.accountID,
                username: outcome.username,
                processIdentifier: outcome.processIdentifier,
                placeID: nil,
                errorMessage: message,
                placementResult: outcome.placementResult
            )
        }

        let placementResults = Dictionary(
            uniqueKeysWithValues: outcomes.compactMap { outcome in
                outcome.placementResult.map { (outcome.accountID, $0) }
            }
        )

        let now = Date()
        for outcome in outcomes where outcome.errorMessage == nil {
            if let index = accounts.firstIndex(where: { $0.id == outcome.accountID }) {
                accounts[index].lastUsed = now
            }
            activeLaunchTargets[outcome.accountID] = nil
        }
        do {
            try saveAccounts(accounts)
            try activeLaunchRepository.save(Array(activeLaunchTargets.values))
        } catch {
            notice = Notice(title: "Launch details were not saved", message: error.localizedDescription)
        }

        let failures = outcomes.filter { $0.errorMessage != nil }
        if failures.isEmpty {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Opened all \(total) apps"
            launchStatus = "Running \(total) Roblox apps"
            showWindowPlacementNoticeIfNeeded(placementResults)
            batchWindowArrangement = .savedPlacements
            batchLaunchSettingsOverride = nil
        } else {
            batchSelectedIDs = Set(failures.map(\.accountID))
            batchStates = batchStates.filter { batchSelectedIDs.contains($0.key) }
            batchStatus = "\(total - failures.count) opened, \(failures.count) failed"
            launchStatus = "\(total - failures.count) running, \(failures.count) failed"
            notice = Notice(
                title: "\(failures.count) account\(failures.count == 1 ? "" : "s") did not open",
                message: launchFailureMessage(failures)
            )
        }
    }

    func launch(
        account: ManagedAccount,
        placeText: String,
        server: RobloxServerSelection,
        rememberSelection: Bool = true,
        friendRelayStep: Bool = false,
        settingsOverride: RobloxLaunchSettings? = nil
    ) async {
        guard !isWorking,
              !isBatchLaunching,
              appOpeningAccountIDs.isEmpty,
              friendRelayStep || !isFriendRelayLaunching else { return }
        guard !isRunning(account) else {
            notice = Notice(title: "Account is already running", message: RobloxLaunchError.accountAlreadyRunning.localizedDescription)
            return
        }
        let enteredPlaceID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines))
        let isUnresolvedShareLink: Bool
        if case .privateLink(let link) = server {
            isUnresolvedShareLink = RobloxLaunchURLBuilder.privateShareCode(from: link) != nil
        } else {
            isUnresolvedShareLink = false
        }
        guard isUnresolvedShareLink || (enteredPlaceID ?? 0) > 0 else {
            notice = Notice(title: "Check the place ID", message: RobloxLaunchError.invalidPlaceID.localizedDescription)
            return
        }
        isWorking = true
        launchStatus = "Checking launch details"
        defer { isWorking = false }

        let placeID = enteredPlaceID ?? 0
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
        launchStatus = "Requesting a launch ticket"

        do {
            guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                throw RobloxAPIError.invalidSession
            }
            if case .privateLink = launchServer {
                launchStatus = "Resolving the private server"
            }
            let resolved = try await resolveServerTarget(
                launchServer,
                placeID: placeID,
                cookie: cookie,
                api: api
            )

            launchStatus = "Requesting a launch ticket"
            let ticket = try await api.authenticationTicket(cookie: cookie)
            let url = try builder.makeURL(
                ticket: ticket,
                placeID: resolved.placeID,
                target: resolved.target
            )
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Preparing a separate Roblox copy"
            case .official:
                launchStatus = "Opening official Roblox"
            case .modifiedParallel:
                launchStatus = "Preparing the advanced fallback copy"
            }
            let instance = try await launcher.launch(
                url,
                for: account.id,
                mode: launchMode,
                settings: settingsOverride ?? launchSettings
            )
            await refreshRunningInstances()
            guard isRunning(account) else {
                throw launchMode == .official
                    ? RobloxLaunchError.officialParallelUnavailable
                    : RobloxLaunchError.openFailed
            }

            var updated = account
            updated.lastUsed = Date()
            if rememberSelection {
                updated.savedPlaceID = String(resolved.placeID)
                updated.savedServer = launchServer.persistedValue
            }
            update(updated)
            recordLaunchTarget(
                accountID: account.id,
                processIdentifier: instance.processIdentifier,
                placeID: resolved.placeID,
                server: launchServer
            )
            recordExperienceLaunch(placeID: resolved.placeID)
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Running @\(account.username) with the recommended method"
            case .official:
                launchStatus = "Running @\(account.username) with official Roblox"
            case .modifiedParallel:
                launchStatus = "Running @\(account.username) with the advanced fallback"
            }
            await applyWindowPlacement(accountID: account.id, processIdentifier: instance.processIdentifier)
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
        guard !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              appOpeningAccountIDs.isEmpty else { return }
        guard let placeID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines)), placeID > 0 else {
            notice = Notice(title: "Check the shared place ID", message: RobloxLaunchError.invalidPlaceID.localizedDescription)
            return
        }

        let selectedAccounts = accounts.filter {
            batchSelectedIDs.contains($0.id) && !isRunning($0) && !isOpeningApp($0)
        }
        guard !selectedAccounts.isEmpty else {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = "Select accounts that are not running"
            return
        }
        isWorking = true
        isBatchLaunching = true
        defer {
            isWorking = false
            isBatchLaunching = false
        }

        let windowArrangement = batchWindowArrangement
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

        var preparedPrivateTargets: [UUID: ResolvedServerTarget] = [:]
        if case .privateLink = launchServer {
            let prepared = await privateServerTargets(
                accounts: selectedAccounts,
                placeID: placeID,
                selection: launchServer
            )
            let denied = prepared.failures
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
            preparedPrivateTargets = prepared.targets
        }

        let vault = self.vault
        let api = self.api
        let builder = self.builder
        let launcher = self.launcher
        let launchMode = self.launchMode
        let launchSettings = batchLaunchSettingsOverride ?? self.launchSettings
        let windowLayout = self.windowLayout
        let privateTargets = preparedPrivateTargets
        let resolvedLaunchServer = launchServer
        let total = selectedAccounts.count

        batchStates = Dictionary(uniqueKeysWithValues: selectedAccounts.map { ($0.id, .starting) })
        batchStatus = "Starting 0 of \(total)"
        launchStatus = "Starting selected accounts"

        var outcomes: [LaunchOutcome] = []
        await withTaskGroup(of: LaunchOutcome.self) { group in
            for account in selectedAccounts {
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }

                        let resolved = if let prepared = privateTargets[account.id] {
                            prepared
                        } else {
                            try await resolveServerTarget(
                                resolvedLaunchServer,
                                placeID: placeID,
                                cookie: cookie,
                                api: api
                            )
                        }

                        let ticket = try await api.authenticationTicket(cookie: cookie)
                        let url = try builder.makeURL(
                            ticket: ticket,
                            placeID: resolved.placeID,
                            target: resolved.target
                        )
                        let instance = try await launcher.launch(
                            url,
                            for: account.id,
                            mode: launchMode,
                            settings: launchSettings
                        )
                        let placementResult = await windowLayout.placeWindow(
                            accountID: account.id,
                            processIdentifier: instance.processIdentifier,
                            arrangement: windowArrangement
                        )
                        return LaunchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: instance.processIdentifier,
                            placeID: resolved.placeID,
                            errorMessage: nil,
                            placementResult: placementResult
                        )
                    } catch {
                        return LaunchOutcome(
                            accountID: account.id,
                            username: account.username,
                            processIdentifier: nil,
                            placeID: nil,
                            errorMessage: error.localizedDescription,
                            placementResult: nil
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
            return LaunchOutcome(
                accountID: outcome.accountID,
                username: outcome.username,
                processIdentifier: outcome.processIdentifier,
                placeID: outcome.placeID,
                errorMessage: message,
                placementResult: outcome.placementResult
            )
        }
        let placementResults = Dictionary(
            uniqueKeysWithValues: outcomes.compactMap { outcome in
                outcome.placementResult.map { (outcome.accountID, $0) }
            }
        )
        for outcome in outcomes where outcome.errorMessage == nil {
            let launchedPlaceID = outcome.placeID ?? placeID
            if let index = accounts.firstIndex(where: { $0.id == outcome.accountID }) {
                accounts[index].lastUsed = Date()
                if rememberSelection {
                    accounts[index].savedPlaceID = String(launchedPlaceID)
                    accounts[index].savedServer = launchServer.persistedValue
                }
            }
            if let processIdentifier = outcome.processIdentifier {
                recordLaunchTarget(
                    accountID: outcome.accountID,
                    processIdentifier: processIdentifier,
                    placeID: launchedPlaceID,
                    server: launchServer
                )
            }
        }
        let launchedPlaceIDs = Set(outcomes.compactMap { $0.errorMessage == nil ? $0.placeID : nil })
        for launchedPlaceID in launchedPlaceIDs { recordExperienceLaunch(placeID: launchedPlaceID) }
        do {
            try saveAccounts(accounts)
        } catch {
            notice = Notice(
                title: "Launch details were not saved",
                message: "Roblox opened, but the recent launch details could not be saved. \(error.localizedDescription)"
            )
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
            showWindowPlacementNoticeIfNeeded(placementResults)
            batchWindowArrangement = .savedPlacements
            batchLaunchSettingsOverride = nil
        } else {
            batchSelectedIDs = Set(failures.map(\.accountID))
            batchStates = batchStates.filter { batchSelectedIDs.contains($0.key) }
            batchStatus = "\(total - failures.count) started, \(failures.count) failed"
            launchStatus = "\(total - failures.count) running, \(failures.count) failed"
            notice = Notice(
                title: "\(failures.count) account\(failures.count == 1 ? "" : "s") did not start",
                message: launchFailureMessage(failures)
            )
        }
    }

    private func updateBatchSelectionStatus() {
        let count = batchSelectedIDs.count
        if count == 0 {
            batchWindowArrangement = .savedPlacements
            batchLaunchSettingsOverride = nil
        }
        batchStatus = count == 0
            ? "Select accounts from the shelf"
            : "\(count) account\(count == 1 ? "" : "s") ready"
    }

    private func applyWindowPlacement(accountID: UUID, processIdentifier: Int32) async {
        let result = await windowLayout.placeWindow(
            accountID: accountID,
            processIdentifier: processIdentifier
        )
        showWindowPlacementNoticeIfNeeded([accountID: result])
    }

    private func showWindowPlacementNoticeIfNeeded(
        _ results: [UUID: WindowPlacementResult]
    ) {
        let accountOrder = Dictionary(
            uniqueKeysWithValues: accounts.enumerated().map { ($0.element.id, $0.offset) }
        )
        let failures = results.compactMap { accountID, result -> (UUID, String)? in
            result.requiresAttentionMessage.map { (accountID, $0) }
        }.sorted {
            accountOrder[$0.0, default: .max] < accountOrder[$1.0, default: .max]
        }
        guard !failures.isEmpty else { return }
        let lines = failures.map { accountID, message in
            let handle = accounts.first(where: { $0.id == accountID }).map { "@\($0.username)" }
                ?? "One account"
            return "\(handle): \(message)"
        }
        notice = Notice(
            title: failures.count == 1
                ? "Roblox opened without its saved layout"
                : "\(failures.count) Roblox windows need attention",
            message: lines.joined(separator: "\n")
        )
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
            try saveAccounts(accounts)
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
        switch server {
        case .automatic:
            kind = .automatic
            jobID = nil
        case .publicInstance(let value, _, _):
            kind = .verifiedPublicJob
            jobID = value
        case .player(_, _, let value), .manualJob(let value):
            kind = .publicJob
            jobID = value
        case .privateLink:
            kind = .privateServer
            jobID = nil
        }
        activeLaunchTargets[accountID] = ActiveLaunchTargetRecord(
            accountID: accountID,
            processIdentifier: processIdentifier,
            placeID: placeID,
            targetKind: kind,
            jobID: jobID,
            privateServerReference: nil
        )
        try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
    }

    private func privateServerTargets(
        accounts: [ManagedAccount],
        placeID: Int64,
        selection: RobloxServerSelection
    ) async -> (targets: [UUID: ResolvedServerTarget], failures: [UUID: String]) {
        let vault = self.vault
        let api = self.api
        var targets: [UUID: ResolvedServerTarget] = [:]
        var failures: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, ResolvedServerTarget?, String?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }
                        let target = try await resolveServerTarget(
                            selection,
                            placeID: placeID,
                            cookie: cookie,
                            api: api
                        )
                        return (account.id, target, nil)
                    } catch {
                        return (account.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (accountID, target, message) in group {
                if let target { targets[accountID] = target }
                if let message { failures[accountID] = message }
            }
        }
        return (targets, failures)
    }

    private func recordExperienceLaunch(placeID: Int64) {
        let now = Date()
        if let index = experiences.firstIndex(where: { $0.placeID == placeID }) {
            experiences[index].lastLaunchedAt = now
            experiences[index].launchCount += 1
        } else {
            experiences.append(ExperienceRecord(
                placeID: placeID,
                lastLaunchedAt: now,
                launchCount: 1
            ))
        }
        experiences.sort { $0.lastLaunchedAt > $1.lastLaunchedAt }
        try? experienceRepository.save(experiences)
        Task { await refreshExperienceMetadata(placeIDs: [placeID], force: true) }
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
        do { try savePrivateServers(privateServers) }
        catch { notice = Notice(title: "Private server list could not be prepared", message: error.localizedDescription) }
    }

    private func privateServerKey(placeID: Int64, link: String) -> String? {
        if let code = RobloxLaunchURLBuilder.privateShareCode(from: link) {
            return "share|\(code.lowercased())"
        }
        guard let code = RobloxLaunchURLBuilder.privateLinkCode(from: link) else { return nil }
        return "legacy|\(placeID)|\(code)"
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

    private func launchFailureMessage(_ failures: [LaunchOutcome]) -> String {
        let shown = failures.prefix(5).map { "@\($0.username): \($0.errorMessage ?? "Unknown error")" }
        let remaining = failures.count - shown.count
        if remaining > 0 {
            return (shown + ["\(remaining) more failed."]).joined(separator: "\n")
        }
        return shown.joined(separator: "\n")
    }
}

private struct ResolvedServerTarget: Sendable {
    let placeID: Int64
    let target: RobloxServerTarget
}

private func resolveServerTarget(
    _ selection: RobloxServerSelection,
    placeID: Int64,
    cookie: String,
    api: any RobloxAPIProviding
) async throws -> ResolvedServerTarget {
    switch selection {
    case .automatic:
        return ResolvedServerTarget(placeID: placeID, target: .publicServer)
    case .player(_, let userID, _):
        guard userID > 0 else { throw RobloxLaunchError.invalidServer }
        return ResolvedServerTarget(placeID: placeID, target: .followUser(userID))
    case .publicInstance(let jobID, _, _), .manualJob(let jobID):
        let clean = jobID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: clean) != nil else { throw RobloxLaunchError.invalidServer }
        return ResolvedServerTarget(placeID: placeID, target: .job(clean))
    case .privateLink(let link):
        if let shareCode = RobloxLaunchURLBuilder.privateShareCode(from: link) {
            let resolution = try await api.privateShareLinkResolution(
                shareCode: shareCode,
                cookie: cookie
            )
            let accessCode = try await api.privateServerAccessCode(
                placeID: resolution.placeID,
                linkCode: resolution.linkCode,
                cookie: cookie
            )
            return ResolvedServerTarget(
                placeID: resolution.placeID,
                target: .privateServer(accessCode: accessCode, linkCode: resolution.linkCode)
            )
        }
        guard let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: link) else {
            throw RobloxLaunchError.invalidServer
        }
        let accessCode = try await api.privateServerAccessCode(
            placeID: placeID,
            linkCode: linkCode,
            cookie: cookie
        )
        return ResolvedServerTarget(
            placeID: placeID,
            target: .privateServer(accessCode: accessCode, linkCode: linkCode)
        )
    }
}

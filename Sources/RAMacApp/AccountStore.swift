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

    enum SessionImportError: LocalizedError {
        case busy

        var errorDescription: String? {
            "Wait for the current task to finish, then try again."
        }
    }

    enum BatchLaunchState: Equatable {
        case starting
        case started
        case accountUnavailable(AccountHealth)
        case failed(String)

        var label: String {
            switch self {
            case .starting: return "Starting"
            case .started: return "Opened"
            case .accountUnavailable(let health): return health.launchIssue
            case .failed: return "Failed"
            }
        }

        var healthMessage: String? {
            guard case .accountUnavailable(let health) = self else { return nil }
            return health.launchIssue
        }

        var errorMessage: String? {
            switch self {
            case .accountUnavailable(let health): return health.launchIssue
            case .failed(let message): return message
            default: return nil
            }
        }
    }

    enum RobloxUpdateRecovery: Equatable {
        case waiting(String, canOpenUpdater: Bool)
        case checking
        case ready
    }

    enum LaunchSetNextStep: Equatable {
        case browsePublicServers
        case choosePlayer
    }

    private struct BatchDestination: Hashable, Sendable {
        let placeID: Int64?
        var server: RobloxServerSelection = .automatic
        var allowPublicFallback = false
    }

    private struct BatchRetry {
        var id = UUID()
        var accountIDs: Set<UUID>
        let windowArrangement: WindowArrangementPolicy
        let settings: RobloxLaunchSettings
        let game: (place: String, server: RobloxServerSelection, rememberSelection: Bool)?
        let destinations: [UUID: BatchDestination]
        var accountGames: [UUID: LaunchSetGame] = [:]
        var accountSettings: [UUID: RobloxLaunchSettings] = [:]
        var preserveSession = false
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
        var updateError: RobloxLaunchError? = nil
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
    @Published private(set) var lastBatchResults: [UUID: BatchLaunchState] = [:]
    @Published private(set) var batchReadyIDs = Set<UUID>()
    @Published private(set) var batchPausedForReview = false
    @Published var batchAccountGames: [UUID: LaunchSetGame] = [:] {
        didSet { if oldValue != batchAccountGames { dismissBatchReview() } }
    }
    @Published var batchAccountSettings: [UUID: RobloxLaunchSettings] = [:] {
        didSet { if oldValue != batchAccountSettings { dismissBatchReview() } }
    }
    @Published private(set) var lastSession: [SessionLaunch] = []
    @Published private(set) var namedWindowLayouts: [NamedWindowLayout] = []
    @Published var batchPlaceID = "" {
        didSet { if oldValue != batchPlaceID { dismissBatchReview() } }
    }
    @Published var batchServerSelection = RobloxServerSelection.automatic {
        didSet { if oldValue != batchServerSelection { dismissBatchReview() } }
    }
    @Published var showsBatchPublicServers = false
    @Published private(set) var launchSetPlayerAccounts: Set<UUID>?
    @Published private(set) var isBatchLaunching = false
    @Published private(set) var isOpeningSelectedApps = false
    @Published var batchWindowArrangement: WindowArrangementPolicy = .savedPlacements {
        didSet { if oldValue != batchWindowArrangement { dismissBatchReview() } }
    }
    @Published var batchLaunchSettingsOverride: RobloxLaunchSettings? = nil {
        didSet { if oldValue != batchLaunchSettingsOverride { dismissBatchReview() } }
    }
    @Published private(set) var appOpeningAccountIDs = Set<UUID>()
    @Published private(set) var isStoppingAll = false
    @Published private(set) var batchStatus = "Select accounts"
    @Published private(set) var robloxUpdateRecovery: RobloxUpdateRecovery?
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
    private let lastSessionRepository: JSONFileRepository<SessionLaunch>
    private let namedLayoutRepository: JSONFileRepository<NamedWindowLayout>
    private let settingsDefaults: UserDefaults
    private let archiveService = MetadataArchiveService()
    private var serverPageCache: [String: PublicServerSnapshot] = [:]
    private let serverCacheLifetime: TimeInterval = 60
    private var didStartInitialAccountCheck = false
    private var friendRelayCancellationRequested = false
    private var friendRelayUpdateError: RobloxLaunchError?
    private var lastBatchRetry: BatchRetry?
    private var updateRetries: [Set<UUID>: @MainActor () async -> Void] = [:]
    private var updateRecoveryID = UUID()
    private var isPollingRunningAccounts = false
    private var sessionPrivateLinks: [UUID: String] = [:]
    private var canSaveProtectedData = false

    private struct SavedDataRecoveryRequired: LocalizedError {
        var errorDescription: String? { "Recover the files listed in the startup warning, then reopen the app." }
    }

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
        self.lastSessionRepository = JSONFileRepository(fileName: "LastSession.json", dataDirectory: repository.dataDirectory)
        self.namedLayoutRepository = JSONFileRepository(fileName: "WindowLayouts.json", dataDirectory: repository.dataDirectory)
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
        canSaveProtectedData = false
        do {
            var storageWarnings: [String] = []
            let loadedAccounts = try repository.loadWithRecovery { account in
                if try self.profileNoteVault.readNote(for: account.id) == nil {
                    try self.profileNoteVault.saveNote(account.notes, for: account.id)
                }
            }
            accounts = loadedAccounts.records
            if loadedAccounts.recoveredFromBackup {
                storageWarnings.append("Accounts were recovered from the last valid backup.")
            }
            var metadataNeedsSave = try loadSecureProfileNotes()
            groups = ManagedAccount.normalizedGroups(
                (try repository.loadGroups()) + accounts.flatMap(\.groups)
            )
            canSaveProtectedData = true
            launchSets = loadStoredRecords(
                from: launchSetRepository,
                name: "Launch Sets",
                containsPrivateLinks: true,
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
                containsPrivateLinks: true,
                warnings: &storageWarnings
            ))
            lastSession = loadStoredRecords(
                from: lastSessionRepository, name: "Last session", containsPrivateLinks: true, warnings: &storageWarnings
            )
            namedWindowLayouts = loadStoredRecords(
                from: namedLayoutRepository, name: "Window layouts", warnings: &storageWarnings
            )
            try loadPrivateServerCapabilities()
            for index in accounts.indices {
                guard privateServerCapabilityKey(from: accounts[index].savedServer) == nil else { continue }
                guard case .manualJob = RobloxServerSelection.savedValue(accounts[index].savedServer) else {
                    continue
                }
                guard !accounts[index].savedServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                accounts[index].savedServer = ""
                metadataNeedsSave = true
            }
            if metadataNeedsSave && canSaveProtectedData {
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
            canSaveProtectedData = false
            notice = Notice(title: "Accounts could not load", message: error.localizedDescription)
        }
    }

    private func loadStoredRecords<Record: Codable & Sendable>(
        from repository: JSONFileRepository<Record>,
        name: String,
        containsPrivateLinks: Bool = false,
        warnings: inout [String]
    ) -> [Record] {
        do {
            let result = try repository.loadWithRecovery()
            if result.recoveredFromBackup {
                warnings.append("\(name) was recovered from its last valid backup.")
            }
            return result.records
        } catch {
            if containsPrivateLinks { canSaveProtectedData = false }
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
        }) || lastSession.contains(where: \.usesPrivateServer) else { return }

        var capabilities = try vault.readPrivateServerCapabilities()
        sessionPrivateLinks = Dictionary(lastSession.compactMap { launch in
            capabilities[privateServerCapabilityKey(kind: "session", id: launch.accountID)].map {
                (launch.accountID, $0)
            }
        }, uniquingKeysWith: { first, _ in first })
        var migrated = false

        for index in accounts.indices {
            let key = privateServerCapabilityKey(kind: "account", id: accounts[index].id)
            let value = accounts[index].savedServer
            if privateServerCapabilityKey(from: value) != nil {
                accounts[index].savedServer = capabilities[key] ?? value
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
                    ?? .privateServerLink(value)
            } else if isPrivateServerLink(value) {
                capabilities[key] = value
                migrated = true
            }
        }
        for index in privateServers.indices {
            let key = privateServerCapabilityKey(kind: "library", id: privateServers[index].id)
            let value = privateServers[index].link
            if privateServerCapabilityKey(from: value) != nil {
                privateServers[index].link = capabilities[key] ?? value
            } else if isPrivateServerLink(value) {
                capabilities[key] = value
                migrated = true
            }
        }

        guard migrated, canSaveProtectedData else { return }
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
        try requireWritableProtectedData()
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
        for (id, link) in sessionPrivateLinks where isPrivateServerLink(link) {
            capabilities[privateServerCapabilityKey(kind: "session", id: id)] = link
        }
        try vault.savePrivateServerCapabilities(capabilities)
    }

    private func requireWritableProtectedData() throws {
        guard canSaveProtectedData else { throw SavedDataRecoveryRequired() }
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
        dismissBatchReview()
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
        dismissBatchReview()
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
        dismissBatchReview()
        batchAccountGames.removeAll()
        batchAccountSettings.removeAll()
        showsBatchPublicServers = false
        batchWindowArrangement = .savedPlacements
        batchLaunchSettingsOverride = nil
        updateBatchSelectionStatus()
    }

    @discardableResult
    func createGroup(_ rawName: String, addingTo accountIDs: Set<UUID> = []) -> String? {
        guard canSaveProtectedData else {
            notice = Notice(title: "Group was not saved", message: SavedDataRecoveryRequired().localizedDescription)
            return nil
        }
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
        for index in accounts.indices where accountIDs.contains(accounts[index].id) {
            guard !accounts[index].belongs(to: groupName) else { continue }
            accounts[index].groups = ManagedAccount.normalizedGroups(accounts[index].groups + [groupName])
        }
        do {
            try repository.saveGroups(groups)
            if !accountIDs.isEmpty { try saveAccounts(accounts) }
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
        guard canSaveProtectedData else {
            notice = Notice(title: "Group was not deleted", message: SavedDataRecoveryRequired().localizedDescription)
            return
        }
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

    func pollRunningAccounts() async {
        guard !isPollingRunningAccounts, !isBusyWithRoblox else { return }
        isPollingRunningAccounts = true
        defer { isPollingRunningAccounts = false }
        await refreshRunningInstances()
    }

    func refreshRunningInstances() async {
        let previousIDs = runningAccountIDs
        let refreshedIDs = await launcher.runningAccountIDs(from: accounts.map(\.id))
        if refreshedIDs != runningAccountIDs {
            runningAccountIDs = refreshedIDs
        }
        if !updateRetries.isEmpty {
            updateRetries = updateRetries.filter { !$0.key.isSubset(of: refreshedIDs) }
            if updateRetries.isEmpty { cancelRobloxUpdateRecovery() }
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

    func bringToFront(_ account: ManagedAccount) async {
        guard await launcher.bringToFront(accountID: account.id) else {
            await refreshRunningInstances()
            notice = Notice(
                title: "Could not bring Roblox forward",
                message: "Check whether Roblox is still open for @\(account.username)."
            )
            return
        }
    }

    private func runningWindowProcesses() async -> [(accountID: UUID, processIdentifier: Int32)] {
        var processes: [(UUID, Int32)] = []
        for account in accounts where runningAccountIDs.contains(account.id) {
            if let pid = await launcher.runningProcessIdentifier(accountID: account.id) {
                processes.append((account.id, pid))
            }
        }
        return processes
    }

    func captureWindowLayout(name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isBusyWithRoblox else { return false }
        guard !namedWindowLayouts.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            notice = Notice(title: "That layout name is in use", message: "Enter a different name.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        await refreshRunningInstances()
        let processes = await runningWindowProcesses()
        let assignments = await windowLayout.captureWindows(processes)
        guard !assignments.isEmpty else {
            notice = Notice(
                title: "No windows were saved",
                message: "Open a Roblox window and allow Window Control, then try again."
            )
            return false
        }
        let saved = saveWindowLayouts(namedWindowLayouts + [NamedWindowLayout(name: name, assignments: assignments)])
        if saved, assignments.count < runningAccountIDs.count {
            notice = Notice(title: "Some windows were skipped", message: "Only visible Roblox windows were saved.")
        }
        return saved
    }

    func applyWindowLayout(_ layout: NamedWindowLayout) async {
        guard !isBusyWithRoblox else { return }
        isWorking = true
        defer { isWorking = false }
        await refreshRunningInstances()
        let processes = await runningWindowProcesses().filter { process in
            layout.assignments.contains { $0.accountID == process.accountID }
        }
        guard !processes.isEmpty else {
            notice = Notice(title: "No matching windows", message: "Start an account in this layout and try again.")
            return
        }
        showWindowPlacementNoticeIfNeeded(await windowLayout.placeWindows(processes, with: layout.assignments))
    }

    func removeWindowLayout(_ layout: NamedWindowLayout) {
        _ = saveWindowLayouts(namedWindowLayouts.filter { $0.id != layout.id })
    }

    private func saveWindowLayouts(_ layouts: [NamedWindowLayout]) -> Bool {
        do {
            try namedLayoutRepository.save(layouts)
            namedWindowLayouts = layouts
            return true
        } catch {
            notice = Notice(title: "Window layouts could not be saved", message: error.localizedDescription)
            return false
        }
    }

    func checkRobloxUpdate(openUpdater: Bool = false) async {
        guard robloxUpdateRecovery != nil, robloxUpdateRecovery != .checking else { return }
        let recoveryID = updateRecoveryID
        robloxUpdateRecovery = .checking
        do {
            try await launcher.checkRobloxVersion(openUpdater: openUpdater)
            guard updateRecoveryID == recoveryID else { return }
            robloxUpdateRecovery = .ready
        } catch {
            guard updateRecoveryID == recoveryID else { return }
            let launchError = error as? RobloxLaunchError
            switch launchError {
            case .robloxUpdateOpened:
                robloxUpdateRecovery = .waiting("Let Roblox finish updating, then quit Roblox and check again.", canOpenUpdater: false)
            case .robloxUpdateRequired:
                let message = openUpdater
                    ? "Quit all Roblox clients before opening the updater."
                    : "Roblox still needs an update. If the installer has finished, try opening it again."
                robloxUpdateRecovery = .waiting(message, canOpenUpdater: true)
            case .robloxUpdaterOpenFailed:
                robloxUpdateRecovery = .waiting(
                    "The installer did not open. Start a game at roblox.com to update Roblox, then check again.",
                    canOpenUpdater: true
                )
            default:
                robloxUpdateRecovery = .waiting(error.localizedDescription, canOpenUpdater: false)
            }
        }
    }

    var isBusyWithRoblox: Bool {
        isWorking || isBatchLaunching || isFriendRelayLaunching || !appOpeningAccountIDs.isEmpty
    }

    func cancelRobloxUpdateRecovery() {
        updateRecoveryID = UUID()
        updateRetries.removeAll()
        robloxUpdateRecovery = nil
    }

    func retryAfterRobloxUpdate() async {
        guard robloxUpdateRecovery == .ready, !isBusyWithRoblox else { return }
        let retries = Array(updateRetries.values)
        cancelRobloxUpdateRecovery()
        for retry in retries { await retry() }
    }

    private func offerUpdateRecovery(
        _ error: RobloxLaunchError?,
        accountIDs: Set<UUID>,
        retry: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard let error, error.blocksLaunchForUpdate else { return false }
        updateRetries[accountIDs] = retry
        updateRecoveryID = UUID()
        if error == .robloxUpdateOpened {
            robloxUpdateRecovery = .waiting("Let Roblox finish updating, then quit Roblox and check again.", canOpenUpdater: false)
        } else if error == .robloxUpdateRequired {
            robloxUpdateRecovery = .waiting("Quit all Roblox clients, then open the Roblox updater.", canOpenUpdater: true)
        } else {
            robloxUpdateRecovery = .waiting(error.localizedDescription, canOpenUpdater: true)
        }
        return true
    }

    var canRetryLastBatch: Bool {
        guard let lastBatchRetry else { return false }
        let eligible = accounts.filter {
            lastBatchRetry.accountIDs.contains($0.id) && !isRunning($0)
        }
        return robloxUpdateRecovery == nil && !isBusyWithRoblox && !eligible.isEmpty
            && eligible.allSatisfy { accountHealth[$0.id]?.needsSignIn != true }
    }

    func retryLastBatch() async {
        guard canRetryLastBatch, let lastBatchRetry else { return }
        await retryBatch(lastBatchRetry)
    }

    var batchReviewID: UUID? {
        batchPausedForReview ? lastBatchRetry?.id : nil
    }

    func dismissBatchReview(expectedID: UUID? = nil) {
        guard expectedID == nil || batchReviewID == expectedID else { return }
        guard !isBatchLaunching, !isOpeningSelectedApps,
              batchPausedForReview || !batchReadyIDs.isEmpty else { return }
        batchReadyIDs.removeAll()
        batchPausedForReview = false
    }

    func launchReadyAccounts(expectedID: UUID? = nil) async {
        guard expectedID == nil || batchReviewID == expectedID else { return }
        guard !batchReadyIDs.isEmpty, !isBusyWithRoblox, var request = lastBatchRetry else { return }
        let ready = batchReadyIDs
        await refreshRunningInstances()
        guard !isBusyWithRoblox, lastBatchRetry?.id == request.id, batchReadyIDs == ready else { return }
        let deferred = request.accountIDs.subtracting(ready)
        let previousResults = lastBatchResults.filter { deferred.contains($0.key) }
        let originalRequest = request
        request.accountIDs = ready
        dismissBatchReview()
        guard await retryBatch(request, refreshRunning: false) else { return }
        lastBatchResults.merge(previousResults) { current, _ in current }
        if !originalRequest.preserveSession {
            batchStates.merge(previousResults) { current, _ in current }
            batchSelectedIDs.formUnion(deferred.subtracting(runningAccountIDs))
            batchWindowArrangement = originalRequest.windowArrangement
            batchLaunchSettingsOverride = originalRequest.settings
            batchAccountGames = originalRequest.accountGames
            batchAccountSettings = originalRequest.accountSettings
        }
        request = originalRequest
        request.accountIDs = deferred.union(lastBatchRetry?.accountIDs ?? [])
        lastBatchRetry = request
    }

    @discardableResult
    private func retryBatch(_ request: BatchRetry, refreshRunning: Bool = true) async -> Bool {
        guard !isBusyWithRoblox else { return false }
        if refreshRunning { await refreshRunningInstances() }
        guard !isBusyWithRoblox else { return false }
        let eligible = accounts.filter { request.accountIDs.contains($0.id) && !isRunning($0) }
        guard !eligible.isEmpty else { return false }
        batchSelectedIDs = Set(eligible.map(\.id))
        batchStates.removeAll()
        batchWindowArrangement = request.windowArrangement
        batchLaunchSettingsOverride = request.settings
        batchAccountGames = request.accountGames
        batchAccountSettings = request.accountSettings
        await executeBatch(request)
        return true
    }

    private func finishBatch(
        _ outcomes: [LaunchOutcome],
        request: BatchRetry,
        wasBlockedBeforeLaunch: Bool = false
    ) {
        lastBatchResults = Dictionary(uniqueKeysWithValues: outcomes.compactMap { outcome in
            if let state = batchStates[outcome.accountID] { return (outcome.accountID, state) }
            return wasBlockedBeforeLaunch ? nil : (outcome.accountID, .started)
        })
        let failedIDs = Set(outcomes.filter { $0.errorMessage != nil || wasBlockedBeforeLaunch }.map(\.accountID))
        var retry = request
        retry.accountIDs = failedIDs
        lastBatchRetry = failedIDs.isEmpty ? nil : retry
        let updateFailures = outcomes.filter { $0.updateError != nil }
        if let error = updateFailures.compactMap(\.updateError).first {
            let ids = Set(updateFailures.map(\.accountID))
            var updateRetry = request
            updateRetry.accountIDs = ids
            let request = updateRetry
            _ = offerUpdateRecovery(error, accountIDs: ids) { [weak self] in
                await self?.retryBatch(request)
            }
        }
    }

    private func sessionEntry(
        accountID: UUID, placeID: Int64?, server: RobloxServerSelection, settings: RobloxLaunchSettings
    ) -> (SessionLaunch, String?) {
        let link: String?
        if case .privateLink(let value) = server, isPrivateServerLink(value) { link = value }
        else { link = nil }
        return (SessionLaunch(
            accountID: accountID, placeID: placeID,
            publicJobID: server.jobIDValue.isEmpty ? nil : server.jobIDValue,
            usesPrivateServer: link != nil, settings: settings
        ), link)
    }

    private func saveSessionEntries(_ entries: [(SessionLaunch, String?)], preservingPrevious: Bool = false) {
        guard !entries.isEmpty else { return }
        let currentIDs = Set(accounts.map(\.id))
        let updatedIDs = Set(entries.map { $0.0.accountID })
        let kept = lastSession.filter {
            currentIDs.contains($0.accountID) && !updatedIDs.contains($0.accountID)
                && (preservingPrevious || runningAccountIDs.contains($0.accountID))
        }
        let keptIDs = Set(kept.map(\.accountID))
        let previousLinks = sessionPrivateLinks
        sessionPrivateLinks = previousLinks.filter { keptIDs.contains($0.key) }
        for (record, link) in entries { sessionPrivateLinks[record.accountID] = link }
        let records = kept + entries.map { $0.0 }
        do {
            if previousLinks != sessionPrivateLinks {
                try savePrivateServerCapabilities(accounts: accounts, launchSets: launchSets, privateServers: privateServers)
            }
            try lastSessionRepository.save(records)
            lastSession = records
        } catch {
            if sessionPrivateLinks != previousLinks {
                sessionPrivateLinks = previousLinks
                try? savePrivateServerCapabilities(accounts: accounts, launchSets: launchSets, privateServers: privateServers)
            }
            notice = Notice(title: "Last Session could not be saved", message: "Roblox opened. This session might not be available to resume.")
        }
    }

    private func forgetSessionAccount(_ id: UUID) {
        let hadPrivateLink = sessionPrivateLinks.removeValue(forKey: id) != nil
        guard hadPrivateLink || lastSession.contains(where: { $0.accountID == id }) else { return }
        lastSession.removeAll { $0.accountID == id }
        do {
            if hadPrivateLink {
                try savePrivateServerCapabilities(accounts: accounts, launchSets: launchSets, privateServers: privateServers)
            }
            try lastSessionRepository.save(lastSession)
        } catch {
            notice = Notice(title: "Last Session could not be updated", message: "The removed account cannot be reopened.")
        }
    }

    func resumeLastSession(accountIDs: Set<UUID>, useAnotherPublicServer: Bool) async {
        guard !isBusyWithRoblox else { return }
        await refreshRunningInstances()
        guard !isBusyWithRoblox else { return }
        let records = lastSession.filter { accountIDs.contains($0.accountID) && !runningAccountIDs.contains($0.accountID) }
        var destinations: [UUID: BatchDestination] = [:]
        var settings: [UUID: RobloxLaunchSettings] = [:]
        for record in records {
            var destination = BatchDestination(placeID: record.placeID)
            if record.usesPrivateServer {
                destination.server = .privateLink(sessionPrivateLinks[record.accountID] ?? "")
            } else if let jobID = record.publicJobID {
                destination.server = .publicInstance(jobID: jobID, playing: 0, maxPlayers: 0)
                destination.allowPublicFallback = useAnotherPublicServer
            }
            destinations[record.accountID] = destination
            settings[record.accountID] = record.settings
        }
        guard !destinations.isEmpty else { return }
        batchSelectedIDs = Set(destinations.keys)
        batchAccountGames.removeAll()
        batchAccountSettings = settings
        await executeBatch(BatchRetry(
            accountIDs: batchSelectedIDs, windowArrangement: .savedPlacements, settings: launchSettings,
            game: nil, destinations: destinations, accountSettings: settings, preserveSession: true
        ))
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
        batchAccountGames.removeAll()
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
        friendRelayUpdateError = nil
        friendRelayPlayerID = player.id
        friendRelayStates = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, .planning) })
        defer {
            isFriendRelayLaunching = false
            friendRelayCancellationRequested = false
            friendRelayUpdateError = nil
        }

        await checkAccounts(accountIDs)
        let notReady = selected.filter { accountHealth[$0.id]?.isReady != true }
        guard notReady.isEmpty else {
            notice = Notice(
                title: "Some accounts are not ready",
                message: "Review the sign-in status of the selected accounts."
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
        if let error = friendRelayUpdateError {
            _ = offerUpdateRecovery(error, accountIDs: failedIDs) { [weak self] in
                guard let self else { return }
                let available = accountIDs.subtracting(self.runningAccountIDs)
                await self.launchFriendPlayer(player, accountIDs: available)
            }
            batchStatus = "Roblox needs an update"
            launchStatus = batchStatus
        } else if friendRelayCancellationRequested {
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
        guard friendRelayUpdateError == nil else {
            friendRelayStates[account.id] = .failed("Roblox needs an update.")
            return false
        }
        friendRelayStates[account.id] = initialState
        batchStatus = startingStatus
        await launch(
            account: account,
            placeText: String(placeID),
            server: server,
            rememberSelection: false,
            friendRelayStep: true,
            settingsOverride: batchAccountSettings[account.id] ?? batchLaunchSettingsOverride
        )
        guard friendRelayUpdateError == nil else { return false }
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

        batchAccountGames.removeAll()
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
            try requireWritableProtectedData()
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

    @discardableResult
    func saveLaunchSet(_ launchSet: LaunchSet) -> Bool {
        var updated = launchSet
        updated.updatedAt = Date()
        var records = launchSets
        if let index = records.firstIndex(where: { $0.id == launchSet.id }) {
            records[index] = updated
        } else {
            records.append(updated)
        }
        records.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return persistLaunchSets(records, failureTitle: "Launch Set was not saved")
    }

    @discardableResult
    private func persistLaunchSets(_ records: [LaunchSet], failureTitle: String) -> Bool {
        do {
            try saveLaunchSets(records)
            launchSets = records
            return true
        } catch {
            try? savePrivateServerCapabilities(accounts: accounts, launchSets: launchSets, privateServers: privateServers)
            notice = Notice(title: failureTitle, message: error.localizedDescription)
            return false
        }
    }

    func setLaunchSetPinned(_ id: UUID, pinned: Bool) {
        guard var launchSet = launchSets.first(where: { $0.id == id }) else { return }
        launchSet.isPinned = pinned
        saveLaunchSet(launchSet)
    }

    func saveBatchAsLaunchSet(name: String, placeID: Int64?, pinned: Bool) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountIDs = accounts.filter { batchSelectedIDs.contains($0.id) }.map(\.id)
        let games = batchAccountGames.filter { batchSelectedIDs.contains($0.key) && $0.value.placeID > 0 }
        let allAccountsHaveGames = LaunchSetGame.covers(Set(accountIDs), games: games)
        let sharedPlaceID = max(0, placeID ?? 0)
        guard !name.isEmpty, !accountIDs.isEmpty, sharedPlaceID > 0 || allAccountsHaveGames else { return false }
        let strategy: ServerStrategy
        switch allAccountsHaveGames ? .automatic : batchServerSelection {
        case .automatic: strategy = .robloxChooses
        case .privateLink(let link): strategy = .privateServerLink(link)
        case .player: strategy = .joinPlayer
        case .manualJob, .publicInstance: strategy = .browseBeforeLaunch
        }
        if strategy == .joinPlayer, !games.isEmpty {
            notice = Notice(
                title: "Choose a different server option",
                message: "Choose a player requires a shared game for all accounts."
            )
            return false
        }
        return saveLaunchSet(LaunchSet(
            name: name,
            accountIDs: accountIDs,
            placeID: sharedPlaceID,
            experienceName: experiences.first(where: { $0.placeID == sharedPlaceID })?.experienceName,
            serverStrategy: strategy,
            launchSettings: batchLaunchSettingsOverride,
            windowArrangement: batchWindowArrangement,
            isPinned: pinned,
            accountGames: games,
            accountSettings: batchAccountSettings.filter { batchSelectedIDs.contains($0.key) }
        ))
    }

    func removeLaunchSet(_ launchSet: LaunchSet) {
        persistLaunchSets(launchSets.filter { $0.id != launchSet.id }, failureTitle: "Launch Set was not removed")
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

    @discardableResult
    func runLaunchSet(_ launchSet: LaunchSet, requestID: UUID = UUID()) async -> LaunchSetNextStep? {
        guard runningLaunchSetID == nil,
              !isWorking,
              !isBatchLaunching,
              !isFriendRelayLaunching,
              appOpeningAccountIDs.isEmpty else { return nil }
        runningLaunchSetID = launchSet.id
        defer { runningLaunchSetID = nil }

        let groupAccountIDs = Set(accounts.filter { account in
            launchSet.groupNames.contains { account.belongs(to: $0) }
        }.map(\.id))
        let requested = Set(launchSet.accountIDs).union(groupAccountIDs)
        batchStates.removeAll()
        batchReadyIDs.removeAll()
        batchPausedForReview = false
        batchSelectedIDs = Set(accounts.filter { requested.contains($0.id) && !isRunning($0) }.map(\.id))
        updateBatchSelectionStatus()
        guard !batchSelectedIDs.isEmpty else {
            notice = Notice(title: "No accounts are ready", message: "Every account in this Launch Set is missing or already running.")
            return nil
        }
        batchWindowArrangement = launchSet.windowArrangement
        batchLaunchSettingsOverride = launchSet.launchSettings
        batchAccountGames = launchSet.accountGames
        batchAccountSettings = launchSet.accountSettings
        let sharedPlace = launchSet.placeID > 0 ? String(launchSet.placeID) : ""
        batchPlaceID = sharedPlace
        batchServerSelection = .automatic
        showsBatchPublicServers = false
        launchSetPlayerAccounts = nil
        if sharedPlace.isEmpty || LaunchSetGame.covers(batchSelectedIDs, games: launchSet.accountGames) {
            await launchBatch(placeText: sharedPlace, server: .automatic, requestID: requestID)
            return nil
        }
        switch launchSet.serverStrategy {
        case .robloxChooses:
            await launchBatch(placeText: sharedPlace, server: .automatic, requestID: requestID)
        case .privateServerLink(let link):
            batchServerSelection = .privateLink(link)
            await launchBatch(placeText: sharedPlace, server: batchServerSelection, requestID: requestID)
        case .browseBeforeLaunch:
            showsBatchPublicServers = true
            return .browsePublicServers
        case .joinPlayer:
            guard batchSelectedIDs.allSatisfy({ (launchSet.accountGames[$0]?.placeID ?? 0) <= 0 }) else {
                notice = Notice(
                    title: "Choose a different server option",
                    message: "Choose a player works when all accounts use the same game."
                )
                return nil
            }
            launchSetPlayerAccounts = batchSelectedIDs
            return .choosePlayer
        }
        return nil
    }

    func takeLaunchSetPlayerAccounts() -> Set<UUID>? {
        defer { launchSetPlayerAccounts = nil }
        return launchSetPlayerAccounts
    }

    func launchFromLibrary(
        accountIDs: Set<UUID>, placeID: Int64, server: RobloxServerSelection, requestID: UUID = UUID()
    ) async {
        guard !isBusyWithRoblox else { return }
        await refreshRunningInstances()
        guard !isBusyWithRoblox else { return }
        let eligible = accounts.filter { accountIDs.contains($0.id) && !isRunning($0) }
        guard !eligible.isEmpty else {
            notice = Notice(title: "No accounts can start", message: "Choose accounts that are not running.")
            return
        }
        clearBatchSelection()
        batchSelectedIDs = Set(eligible.map(\.id))
        await launchBatch(placeText: String(placeID), server: server, requestID: requestID)
    }

    func setExperienceFavorite(_ experience: ExperienceRecord, isFavorite: Bool) {
        guard let index = experiences.firstIndex(where: { $0.placeID == experience.placeID }) else { return }
        experiences[index].isFavorite = isFavorite
        do { try experienceRepository.save(experiences) }
        catch { notice = Notice(title: "Favorite was not saved", message: error.localizedDescription) }
    }

    func addGameToLibrary(_ experience: ExperienceRecord) {
        if experiences.contains(where: { $0.placeID == experience.placeID }) {
            setExperienceFavorite(experience, isFavorite: true)
            return
        }
        var favorite = experience
        favorite.isFavorite = true
        do {
            try experienceRepository.save(experiences + [favorite])
            experiences.append(favorite)
        } catch {
            notice = Notice(title: "Game could not be saved", message: error.localizedDescription)
        }
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

    func runDiagnostics() async -> DiagnosticReport {
        await DiagnosticService(accountRepository: repository, vault: vault).run()
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
        try requireWritableProtectedData()
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

    func importSession(_ rawCookie: String) async throws {
        guard !isWorking else { throw SessionImportError.busy }
        try requireWritableProtectedData()
        let cookie = RobloxAPIClient.normalizedCookie(from: rawCookie)
        guard !cookie.isEmpty else { throw RobloxAPIError.invalidSession }
        isWorking = true
        defer { isWorking = false }
        let user = try await api.authenticatedUser(cookie: cookie)
        let avatarURL = await api.avatarURL(userID: user.id)
        try Task.checkCancellation()

        var updated = accounts
        var account = accounts.first { $0.userID == user.id } ?? ManagedAccount(
            userID: user.id, username: user.name, displayName: user.displayName
        )
        account.username = user.name
        account.displayName = user.displayName
        account.avatarURLString = avatarURL?.absoluteString
        let existingIndex = updated.firstIndex { $0.id == account.id }
        if let existingIndex {
            updated[existingIndex] = account
        } else {
            updated.append(account)
        }
        try vault.save(cookie, for: account.id)
        do {
            try saveAccounts(updated)
        } catch {
            if existingIndex == nil { try? vault.delete(for: account.id) }
            throw error
        }
        accounts = updated
        selectedID = account.id
        accountHealth[account.id] = .ready(lastChecked: Date())
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
        guard canSaveProtectedData else {
            notice = Notice(title: "Changes were not saved", message: SavedDataRecoveryRequired().localizedDescription)
            return
        }
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
        guard canSaveProtectedData else {
            notice = Notice(title: "Account was not removed", message: SavedDataRecoveryRequired().localizedDescription)
            return
        }
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
            forgetSessionAccount(account.id)
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
            notice = Notice(title: "Could not open Roblox", message: accountHealth[account.id]?.launchIssue ?? "Check this account and try again.")
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

            await refreshRunningInstances()
            guard isRunning(account) else {
                throw launchMode == .official
                    ? RobloxLaunchError.officialParallelUnavailable
                    : RobloxLaunchError.unmodifiedParallelUnavailable("Roblox closed before the manager could confirm that it was running.")
            }

            var updated = account
            updated.lastUsed = Date()
            update(updated)
            activeLaunchTargets[account.id] = nil
            try? activeLaunchRepository.save(Array(activeLaunchTargets.values))
            saveSessionEntries([sessionEntry(
                accountID: account.id, placeID: nil, server: .automatic, settings: launchSettings
            )])
            switch launchMode {
            case .unmodifiedParallel:
                launchStatus = "Roblox is open as @\(account.username)"
            case .official:
                launchStatus = "Official Roblox is open as @\(account.username)"
            case .modifiedParallel:
                launchStatus = "Fallback Roblox is open as @\(account.username)"
            }
            await applyWindowPlacement(accountID: account.id, processIdentifier: instance.processIdentifier)
        } catch {
            launchStatus = "Open failed"
            let accountID = account.id
            if offerUpdateRecovery(error as? RobloxLaunchError, accountIDs: [accountID], retry: { [weak self] in
                guard let self, let account = self.accounts.first(where: { $0.id == accountID }),
                      !self.isRunning(account) else { return }
                await self.launchApp(account: account)
            }) { return }
            notice = Notice(title: "Roblox did not open", message: error.localizedDescription)
        }
    }

    func launchSelectedApps(skipHealthPreflight: Bool = false) async {
        let destinations = batchSelectedIDs.reduce(into: [UUID: BatchDestination]()) {
            $0[$1] = BatchDestination(placeID: nil)
        }
        await executeBatch(BatchRetry(
            accountIDs: batchSelectedIDs,
            windowArrangement: batchWindowArrangement,
            settings: batchLaunchSettingsOverride ?? launchSettings,
            game: nil, destinations: destinations,
            accountGames: batchAccountGames, accountSettings: batchAccountSettings
        ), skipHealthPreflight: skipHealthPreflight)
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
            notice = Notice(title: "Could not start Roblox", message: accountHealth[account.id]?.launchIssue ?? "Check this account and try again.")
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

            launchStatus = "Connecting to Roblox"
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
            saveSessionEntries([sessionEntry(
                accountID: account.id, placeID: resolved.placeID, server: launchServer,
                settings: settingsOverride ?? launchSettings
            )])
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
            let accountID = account.id
            if friendRelayStep, let launchError = error as? RobloxLaunchError, launchError.blocksLaunchForUpdate {
                friendRelayUpdateError = launchError
                friendRelayStates[accountID] = .failed("Roblox needs an update.")
                return
            }
            if !friendRelayStep, offerUpdateRecovery(error as? RobloxLaunchError, accountIDs: [accountID], retry: { [weak self] in
                guard let self, let account = self.accounts.first(where: { $0.id == accountID }),
                      !self.isRunning(account) else { return }
                await self.launch(
                    account: account, placeText: placeText, server: server,
                    rememberSelection: rememberSelection, settingsOverride: settingsOverride
                )
            }) { return }
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
        rememberSelection: Bool = true,
        requestID: UUID = UUID()
    ) async {
        let parsedPlaceID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let placeID: Int64? = parsedPlaceID > 0 ? parsedPlaceID : nil
        guard placeID != nil || LaunchSetGame.covers(batchSelectedIDs, games: batchAccountGames) else {
            notice = Notice(title: "Choose a game", message: "Choose a shared game or give each account its own game in Per-Account Options.")
            return
        }
        let targets = Dictionary(uniqueKeysWithValues: batchSelectedIDs.map { id in
            let destination: BatchDestination
            if let game = batchAccountGames[id], game.placeID > 0 {
                let server = game.privateServerID.map { serverID in
                    RobloxServerSelection.privateLink(privateServers.first { $0.id == serverID }?.link ?? "")
                } ?? .automatic
                destination = BatchDestination(placeID: game.placeID, server: server)
            } else {
                destination = BatchDestination(placeID: placeID, server: server)
            }
            return (id, destination)
        })
        let request = BatchRetry(
            id: requestID,
            accountIDs: batchSelectedIDs,
            windowArrangement: batchWindowArrangement,
            settings: batchLaunchSettingsOverride ?? launchSettings,
            game: (placeID.map(String.init) ?? "", server, rememberSelection),
            destinations: targets,
            accountGames: batchAccountGames,
            accountSettings: batchAccountSettings
        )
        await executeBatch(request, skipPublicServerPreflight: skipPublicServerPreflight, skipHealthPreflight: skipHealthPreflight)
    }

    private func executeBatch(
        _ request: BatchRetry,
        skipPublicServerPreflight: Bool = false,
        skipHealthPreflight: Bool = false
    ) async {
        guard !isBusyWithRoblox else { return }
        let destinations = request.destinations
        let selectedAccounts = accounts.filter {
            request.accountIDs.contains($0.id) && !isRunning($0) && !isOpeningApp($0) && destinations[$0.id] != nil
        }
        guard !selectedAccounts.isEmpty else {
            clearBatchSelection()
            return
        }

        let opensAppsOnly = request.game == nil && !request.preserveSession
        let selectedIDs = Set(selectedAccounts.map(\.id))
        isWorking = true
        isOpeningSelectedApps = opensAppsOnly
        isBatchLaunching = !opensAppsOnly
        if opensAppsOnly { appOpeningAccountIDs.formUnion(selectedIDs) }
        defer {
            if request.preserveSession {
                batchSelectedIDs.removeAll()
                batchStates.removeAll()
                batchWindowArrangement = .savedPlacements
                batchLaunchSettingsOverride = nil
                batchAccountGames.removeAll()
                batchAccountSettings.removeAll()
            }
            isWorking = false
            isBatchLaunching = false
            isOpeningSelectedApps = false
            if opensAppsOnly { appOpeningAccountIDs.subtract(selectedIDs) }
        }
        batchStates.removeAll()
        batchReadyIDs.removeAll()
        batchPausedForReview = false
        if let game = request.game {
            batchPlaceID = game.place
            batchServerSelection = game.server
        }
        let windowArrangement = request.windowArrangement
        let launchSettings = request.settings
        let accountSettings = request.accountSettings
        if !skipHealthPreflight {
            await checkAccounts(Set(selectedAccounts.map(\.id)))
            for account in selectedAccounts {
                let health = accountHealth[account.id] ?? .unchecked
                if !health.isReady { batchStates[account.id] = .accountUnavailable(health) }
            }
        }

        let candidates = selectedAccounts.filter { batchStates[$0.id] == nil }
        var groups: [BatchDestination: [ManagedAccount]] = [:]
        for account in candidates {
            if let destination = destinations[account.id] {
                groups[destination, default: []].append(account)
            }
        }
        var preparedPrivateTargets: [UUID: ResolvedServerTarget] = [:]
        var checkedDestinations = destinations
        var privateDenied = Set<UUID>()
        var blockedNotice: Notice?
        for (destination, group) in groups {
            guard let placeID = destination.placeID else { continue }
            switch destination.server {
            case .publicInstance(let jobID, _, _) where !skipPublicServerPreflight || destination.allowPublicFallback:
                let verification = await verifyPublicServer(
                    placeID: placeID, jobID: jobID, maximumPages: 100, forceRefresh: true
                )
                if case .verifiedPublic(let current) = verification, current.openSpaces >= group.count {
                    continue
                }
                if destination.allowPublicFallback {
                    for account in group { checkedDestinations[account.id]?.server = .automatic }
                    continue
                }
                if case .verifiedPublic(let current) = verification {
                    let capacity = max(0, current.openSpaces)
                    for account in group.dropFirst(capacity) {
                        batchStates[account.id] = .failed("There is no room for this account in the selected server.")
                    }
                    blockedNotice = Notice(
                        title: "The server no longer has enough space",
                        message: "It has \(capacity) open spaces for \(group.count) accounts. Review the ready accounts before launching."
                    )
                } else {
                    for account in group {
                        batchStates[account.id] = .failed("Choose another public server.")
                    }
                    blockedNotice = Notice(
                        title: "The selected server is no longer public",
                        message: "Choose another server or let Roblox choose."
                    )
                }
            case .privateLink(let link):
                guard !link.isEmpty else {
                    for account in group { batchStates[account.id] = .failed("Choose a saved private server for this account.") }
                    continue
                }
                let prepared = await privateServerTargets(accounts: group, placeID: placeID, selection: destination.server)
                preparedPrivateTargets.merge(prepared.targets) { current, _ in current }
                for (id, message) in prepared.failures {
                    batchStates[id] = .failed(message)
                    privateDenied.insert(id)
                }
                if !prepared.failures.isEmpty {
                    blockedNotice = Notice(
                        title: "Some accounts cannot access this private server",
                        message: "Review the results before starting the accounts that can join."
                    )
                }
            default:
                break
            }
        }
        if !batchStates.isEmpty {
            let blocked = selectedAccounts.map { account in
                LaunchOutcome(
                    accountID: account.id, username: account.username, processIdentifier: nil,
                    placeID: nil, errorMessage: batchStates[account.id]?.errorMessage, placementResult: nil
                )
            }
            batchReadyIDs = Set(selectedAccounts.filter { batchStates[$0.id] == nil }.map(\.id))
            batchPausedForReview = true
            batchSelectedIDs.subtract(privateDenied)
            batchStatus = "Launch paused. Review the account results."
            finishBatch(blocked, request: request, wasBlockedBeforeLaunch: true)
            if batchReadyIDs.isEmpty { notice = blockedNotice }
            return
        }

        let vault = self.vault
        let api = self.api
        let builder = self.builder
        let launcher = self.launcher
        let launchMode = self.launchMode
        let windowLayout = self.windowLayout
        let privateTargets = preparedPrivateTargets
        let finalDestinations = checkedDestinations
        let total = selectedAccounts.count

        batchStates = Dictionary(uniqueKeysWithValues: selectedAccounts.map { ($0.id, .starting) })
        batchStatus = opensAppsOnly ? "Opening 0 of \(total) apps" : "Starting 0 of \(total)"
        launchStatus = opensAppsOnly ? "Opening selected Roblox apps" : "Starting selected accounts"

        var outcomes: [LaunchOutcome] = []
        await withTaskGroup(of: LaunchOutcome.self) { group in
            for account in selectedAccounts {
                guard let destination = finalDestinations[account.id] else { continue }
                let settings = accountSettings[account.id] ?? launchSettings
                group.addTask {
                    do {
                        guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                            throw RobloxAPIError.invalidSession
                        }

                        let ticket = try await api.authenticationTicket(cookie: cookie)
                        let url: URL
                        let launchedPlaceID: Int64?
                        if let placeID = destination.placeID {
                            let resolved: ResolvedServerTarget
                            if let prepared = privateTargets[account.id] {
                                resolved = prepared
                            } else {
                                resolved = try await resolveServerTarget(
                                    destination.server, placeID: placeID, cookie: cookie, api: api
                                )
                            }
                            url = try builder.makeURL(ticket: ticket, placeID: resolved.placeID, target: resolved.target)
                            launchedPlaceID = resolved.placeID
                        } else {
                            url = try builder.makeAppURL(ticket: ticket)
                            launchedPlaceID = nil
                        }
                        let instance = try await launcher.launch(
                            url,
                            for: account.id,
                            mode: launchMode,
                            settings: settings
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
                            placeID: launchedPlaceID,
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
                            placementResult: nil,
                            updateError: (error as? RobloxLaunchError)?.blocksLaunchForUpdate == true
                                ? error as? RobloxLaunchError : nil
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
                batchStatus = opensAppsOnly ? "Opened \(started) of \(total) apps" : "Started \(started) of \(total)"
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
        var sessionEntries: [(SessionLaunch, String?)] = []
        for outcome in outcomes where outcome.errorMessage == nil {
            guard let destination = finalDestinations[outcome.accountID] else { continue }
            if let index = accounts.firstIndex(where: { $0.id == outcome.accountID }) {
                accounts[index].lastUsed = Date()
                if request.game?.rememberSelection == true, let placeID = outcome.placeID {
                    accounts[index].savedPlaceID = String(placeID)
                    accounts[index].savedServer = destination.server.persistedValue
                }
            }
            if let processIdentifier = outcome.processIdentifier, let placeID = outcome.placeID {
                recordLaunchTarget(
                    accountID: outcome.accountID, processIdentifier: processIdentifier,
                    placeID: placeID, server: destination.server
                )
            }
            sessionEntries.append(sessionEntry(
                accountID: outcome.accountID, placeID: outcome.placeID, server: destination.server,
                settings: accountSettings[outcome.accountID] ?? launchSettings
            ))
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

        saveSessionEntries(sessionEntries, preservingPrevious: request.preserveSession)
        finishBatch(outcomes, request: request)
        let failures = outcomes.filter { $0.errorMessage != nil }
        if failures.isEmpty {
            batchSelectedIDs.removeAll()
            batchStates.removeAll()
            batchStatus = opensAppsOnly ? "Opened all \(total) apps" : "Started all \(total) accounts"
            if opensAppsOnly {
                launchStatus = "Running \(total) Roblox app\(total == 1 ? "" : "s")"
            } else {
                switch launchMode {
                case .unmodifiedParallel:
                    launchStatus = "Running \(total) accounts with the recommended method"
                case .official:
                    launchStatus = "Running \(total) accounts with official Roblox"
                case .modifiedParallel:
                    launchStatus = "Running \(total) accounts with the advanced fallback"
                }
            }
            showWindowPlacementNoticeIfNeeded(placementResults)
            batchWindowArrangement = .savedPlacements
            batchLaunchSettingsOverride = nil
            batchAccountGames.removeAll()
            batchAccountSettings.removeAll()
        } else {
            batchSelectedIDs = Set(failures.map(\.accountID))
            batchStates = batchStates.filter { batchSelectedIDs.contains($0.key) }
            batchStatus = "\(total - failures.count) started, \(failures.count) failed"
            launchStatus = "\(total - failures.count) running, \(failures.count) failed"
            if failures.contains(where: { $0.updateError == nil }) {
                notice = Notice(
                    title: "\(failures.count) account\(failures.count == 1 ? "" : "s") did not start",
                    message: launchFailureMessage(failures)
                )
            }
        }
    }

    private func updateBatchSelectionStatus() {
        let count = batchSelectedIDs.count
        if count == 0 {
            batchWindowArrangement = .savedPlacements
            batchLaunchSettingsOverride = nil
            batchAccountGames.removeAll()
            batchAccountSettings.removeAll()
        }
        batchStatus = count == 0
            ? "Select accounts"
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

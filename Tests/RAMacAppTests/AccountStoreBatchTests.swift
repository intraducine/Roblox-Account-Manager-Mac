import Foundation
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class AccountStoreBatchTests: XCTestCase {
    func testLaunchModeDefaultsToUnmodifiedAndFallbackIsSessionOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-mode-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = BatchMockLauncher(failingAccountID: nil)

        let initial = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher
        )
        XCTAssertEqual(initial.launchMode, .unmodifiedParallel)

        initial.setLaunchMode(.modifiedParallel)
        XCTAssertEqual(initial.launchMode, .modifiedParallel)
        let reloaded = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher
        )
        XCTAssertEqual(reloaded.launchMode, .unmodifiedParallel)
    }

    func testGroupSelectionTogglesEveryEligibleAccount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        XCTAssertEqual(fixture.store.batchSelectedIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertTrue(fixture.store.isBatchGroupSelected("Wave"))

        fixture.store.toggleBatchGroup("Wave")
        XCTAssertTrue(fixture.store.batchSelectedIDs.isEmpty)
        XCTAssertFalse(fixture.store.isBatchGroupSelected("Wave"))
    }

    func testAccountCanJoinSeveralGroupsAndEachGroupCanSelectIt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = fixture.store.createGroup("Favorites", addingTo: fixture.accounts[0].id)
        let updated = try XCTUnwrap(fixture.store.accounts.first(where: { $0.id == fixture.accounts[0].id }))
        XCTAssertTrue(updated.belongs(to: "Wave"))
        XCTAssertTrue(updated.belongs(to: "Favorites"))

        fixture.store.toggleBatchGroup("Favorites")
        XCTAssertEqual(fixture.store.batchSelectedIDs, [fixture.accounts[0].id])
    }

    func testIndividualBatchSelectionSelectsAndDeselectsOnlyTheTargetAccount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchSelection(fixture.accounts[1])
        XCTAssertEqual(fixture.store.batchSelectedIDs, [fixture.accounts[1].id])

        fixture.store.toggleBatchSelection(fixture.accounts[1])
        XCTAssertTrue(fixture.store.batchSelectedIDs.isEmpty)
    }

    func testBatchLaunchStartsRequestsTogetherAndKeepsOnlyFailuresSelected() async throws {
        let fixture = try makeFixture(failingIndex: 1)
        let jobID = "11111111-2222-3333-4444-555555555555"
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchBatch(placeText: "12345", serverText: jobID)

        let maximumConcurrentRequests = await fixture.api.maximumConcurrentTicketRequests()
        let attemptedAccountIDs = await fixture.launcher.attemptedAccountIDs()
        let attemptedModes = await fixture.launcher.attemptedModes()
        let runningAccountIDs = await fixture.launcher.runningAccountIDs(from: fixture.accounts.map(\.id))
        XCTAssertEqual(maximumConcurrentRequests, 3)
        XCTAssertEqual(attemptedAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(attemptedModes, [.unmodifiedParallel])
        XCTAssertEqual(runningAccountIDs, Set([fixture.accounts[0].id, fixture.accounts[2].id]))
        XCTAssertEqual(fixture.store.batchSelectedIDs, Set([fixture.accounts[1].id]))
        XCTAssertEqual(fixture.store.batchStatus, "2 started, 1 failed")
        XCTAssertEqual(fixture.store.launchStatus, "2 running, 1 failed")
        XCTAssertEqual(fixture.store.notice?.title, "1 account did not start")
        guard case .failed = fixture.store.batchStates[fixture.accounts[1].id] else {
            return XCTFail("The failed account must stay marked for retry.")
        }

        let saved = try fixture.repository.load()
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[0].id })?.savedPlaceID, "12345")
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[0].id })?.savedServer, jobID)
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[1].id })?.savedPlaceID, "")
    }

    func testStopAllStopsEveryRunningAccount() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchBatch(placeText: "12345", serverText: "")
        XCTAssertEqual(fixture.store.runningAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(fixture.store.launchStatus, "Running 3 accounts with the recommended method")

        await fixture.store.stopAll()

        XCTAssertTrue(fixture.store.runningAccountIDs.isEmpty)
        XCTAssertEqual(fixture.store.launchStatus, "Stopped all Roblox clients")
        XCTAssertEqual(fixture.store.batchStatus, "All Roblox clients stopped")
    }

    func testPublicServerPagesAreCachedToProtectRobloxRateLimit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let first = try await fixture.store.publicServerPage(placeID: 1818)
        let second = try await fixture.store.publicServerPage(placeID: 1818)
        let cachedRequestCount = await fixture.api.publicServerRequestCount()
        _ = try await fixture.store.publicServerPage(placeID: 1818, forceRefresh: true)
        let refreshedRequestCount = await fixture.api.publicServerRequestCount()

        XCTAssertEqual(first.page, second.page)
        XCTAssertEqual(cachedRequestCount, 1)
        XCTAssertEqual(refreshedRequestCount, 2)
    }

    func testJoinablePlayerServerUsesPublicPresence() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try await fixture.store.joinableServer(for: "builderman")

        XCTAssertEqual(result.user.name, "builderman")
        XCTAssertEqual(result.presence.placeId, 1818)
        XCTAssertEqual(result.presence.gameId, "11111111-2222-3333-4444-555555555555")
    }

    func testWebCookieRotationSavesOnlyTheSameRobloxUser() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-web-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "same", displayName: "Same")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: [
            "old": RobloxUser(id: 44, name: "same", displayName: "Same"),
            "rotated": RobloxUser(id: 44, name: "same", displayName: "Same")
        ])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: "rotated")

        XCTAssertEqual(try vault.read(for: account.id), "rotated")
        XCTAssertTrue(store.accountHealth[account.id]?.isReady == true)
    }

    func testWebCookieFromWrongAccountIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-wrong-web-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "expected", displayName: "Expected")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: ["wrong": RobloxUser(id: 99, name: "wrong", displayName: "Wrong")])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: "wrong")

        XCTAssertEqual(try vault.read(for: account.id), "old")
        XCTAssertEqual(store.accountHealth[account.id], .wrongAccount(actualUserID: 99))
    }

    func testWebLogoutChecksWhetherSavedSessionStillWorks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-web-logout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let account = ManagedAccount(userID: 44, username: "same", displayName: "Same")
        try repository.save([account])
        let vault = MemoryVault()
        try vault.save("old", for: account.id)
        let api = WebSessionMockAPI(usersByCookie: ["old": RobloxUser(id: 44, name: "same", displayName: "Same")])
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: BatchMockLauncher(failingAccountID: nil))

        await store.synchronizeWebSession(accountID: account.id, cookie: nil)

        XCTAssertTrue(store.accountHealth[account.id]?.isReady == true)
        XCTAssertEqual(try vault.read(for: account.id), "old")
    }

    func testPrivateServerAccessDenialsAppearBeforeAnyLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-private-preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = [
            ManagedAccount(userID: 1, username: "allowed", displayName: "Allowed", group: "Wave"),
            ManagedAccount(userID: 2, username: "denied", displayName: "Denied", group: "Wave")
        ]
        try repository.save(accounts)
        let vault = MemoryVault()
        try vault.save("allow", for: accounts[0].id)
        try vault.save("deny", for: accounts[1].id)
        let launcher = BatchMockLauncher(failingAccountID: nil)
        let api = PrivateAccessMockAPI()
        let store = AccountStore(repository: repository, vault: vault, api: api, launcher: launcher)
        store.toggleBatchGroup("Wave")

        await store.launchBatch(
            placeText: "1818",
            server: .privateLink("https://www.roblox.com/games/1818?privateServerLinkCode=private-code")
        )

        let attemptedAccountIDs = await launcher.attemptedAccountIDs()
        XCTAssertTrue(attemptedAccountIDs.isEmpty)
        XCTAssertEqual(store.batchSelectedIDs, [accounts[0].id])
        guard case .failed = store.batchStates[accounts[1].id] else {
            return XCTFail("Denied account must be shown before launch")
        }
    }

    private func makeFixture(failingIndex: Int? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-batch-tests-\(UUID().uuidString)", isDirectory: true)
        let repository = AccountRepository(dataDirectory: directory)
        let accounts = (0..<3).map { index in
            ManagedAccount(
                userID: Int64(index + 1),
                username: "account_\(index + 1)",
                displayName: "Account \(index + 1)",
                group: "Wave"
            )
        }
        try repository.save(accounts)

        let vault = MemoryVault()
        for account in accounts {
            try vault.save("cookie-\(account.userID)", for: account.id)
        }
        let api = BatchMockAPI()
        let failingID = failingIndex.map { accounts[$0].id }
        let launcher = BatchMockLauncher(failingAccountID: failingID)
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: api,
            launcher: launcher,
            launchMode: .unmodifiedParallel
        )
        return Fixture(
            directory: directory,
            repository: repository,
            accounts: accounts,
            api: api,
            launcher: launcher,
            store: store
        )
    }
}

private actor WebSessionMockAPI: RobloxAPIProviding {
    let usersByCookie: [String: RobloxUser]
    init(usersByCookie: [String: RobloxUser]) { self.usersByCookie = usersByCookie }
    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        guard let user = usersByCookie[RobloxAPIClient.normalizedCookie(from: rawCookie)] else {
            throw RobloxAPIError.invalidSession
        }
        return user
    }
    func avatarURL(userID: Int64) async -> URL? { nil }
    func authenticationTicket(cookie rawCookie: String) async throws -> String { "ticket" }
    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String { "access" }
}

private actor PrivateAccessMockAPI: RobloxAPIProviding {
    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        if rawCookie == "allow" { return RobloxUser(id: 1, name: "allowed", displayName: "Allowed") }
        if rawCookie == "deny" { return RobloxUser(id: 2, name: "denied", displayName: "Denied") }
        throw RobloxAPIError.invalidSession
    }
    func avatarURL(userID: Int64) async -> URL? { nil }
    func authenticationTicket(cookie rawCookie: String) async throws -> String { "ticket" }
    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String {
        if rawCookie == "deny" { throw RobloxAPIError.privateServerUnavailable }
        return "access"
    }
}

private struct Fixture {
    let directory: URL
    let repository: AccountRepository
    let accounts: [ManagedAccount]
    let api: BatchMockAPI
    let launcher: BatchMockLauncher
    let store: AccountStore
}

private final class MemoryVault: SecretVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]

    func save(_ secret: String, for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        values[accountID] = secret
    }

    func read(for accountID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[accountID]
    }

    func delete(for accountID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        values[accountID] = nil
    }
}

private actor BatchMockAPI: RobloxAPIProviding {
    private var activeTicketRequests = 0
    private var maximumActiveTicketRequests = 0
    private var publicServerRequests = 0

    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        guard let userID = Int64(rawCookie.replacingOccurrences(of: "cookie-", with: "")) else {
            throw RobloxAPIError.invalidSession
        }
        return RobloxUser(id: userID, name: "account_\(userID)", displayName: "Account \(userID)")
    }

    func avatarURL(userID: Int64) async -> URL? { nil }

    func authenticationTicket(cookie rawCookie: String) async throws -> String {
        activeTicketRequests += 1
        maximumActiveTicketRequests = max(maximumActiveTicketRequests, activeTicketRequests)
        try await Task.sleep(nanoseconds: 100_000_000)
        activeTicketRequests -= 1
        return "ticket-\(rawCookie)"
    }

    func privateServerAccessCode(placeID: Int64, linkCode: String, cookie rawCookie: String) async throws -> String {
        "access-\(rawCookie)"
    }

    func publicServers(placeID: Int64, cursor: String?) async throws -> RobloxPublicServerPage {
        publicServerRequests += 1
        return RobloxPublicServerPage(data: [
            RobloxPublicServer(
                id: "11111111-2222-3333-4444-555555555555",
                maxPlayers: 8,
                playing: 2,
                ping: 80
            )
        ])
    }

    func user(named username: String) async throws -> RobloxUserSearchResult {
        RobloxUserSearchResult(id: 156, name: "builderman", displayName: "builderman")
    }

    func presence(userID: Int64) async throws -> RobloxUserPresence {
        RobloxUserPresence(
            userPresenceType: 2,
            lastLocation: "Test Place",
            placeId: 1818,
            rootPlaceId: 1818,
            gameId: "11111111-2222-3333-4444-555555555555",
            universeId: 13058,
            userId: userID
        )
    }

    func maximumConcurrentTicketRequests() -> Int {
        maximumActiveTicketRequests
    }

    func publicServerRequestCount() -> Int {
        publicServerRequests
    }
}

private actor BatchMockLauncher: ParallelRobloxLaunching {
    private let failingAccountID: UUID?
    private var attempted = Set<UUID>()
    private var modes = Set<RobloxLaunchMode>()
    private var running = Set<UUID>()

    init(failingAccountID: UUID?) {
        self.failingAccountID = failingAccountID
    }

    func launch(
        _ url: URL,
        for accountID: UUID,
        mode: RobloxLaunchMode
    ) async throws -> ParallelRobloxInstance {
        attempted.insert(accountID)
        modes.insert(mode)
        if accountID == failingAccountID { throw RobloxLaunchError.openFailed }
        running.insert(accountID)
        return ParallelRobloxInstance(
            accountID: accountID,
            processIdentifier: Int32(attempted.count),
            applicationURL: URL(fileURLWithPath: "/tmp/Roblox.app")
        )
    }

    func runningAccountIDs(from accountIDs: [UUID]) async -> Set<UUID> {
        running.intersection(accountIDs)
    }

    func stop(accountID: UUID) async -> Bool {
        running.remove(accountID)
        return true
    }

    func removeStaleCopies() async {}

    func removePreparedCopy(accountID: UUID) async {}

    func attemptedAccountIDs() -> Set<UUID> {
        attempted
    }

    func attemptedModes() -> Set<RobloxLaunchMode> {
        modes
    }
}

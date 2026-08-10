import Foundation
import XCTest
@testable import RAMacApp
@testable import RAMacCore

@MainActor
final class AccountStoreBatchTests: XCTestCase {
    func testLaunchModeDefaultsToUnmodifiedAndPersistsExplicitFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-mode-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "RAMacAppModeTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let launcher = BatchMockLauncher(failingAccountID: nil)

        let initial = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher,
            preferences: preferences
        )
        XCTAssertEqual(initial.launchMode, .unmodifiedParallel)

        initial.setLaunchMode(.modifiedParallel)
        let reloaded = AccountStore(
            repository: AccountRepository(dataDirectory: directory),
            vault: MemoryVault(),
            api: BatchMockAPI(),
            launcher: launcher,
            preferences: preferences
        )
        XCTAssertEqual(reloaded.launchMode, .modifiedParallel)
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

    func testBatchLaunchStartsRequestsTogetherAndKeepsOnlyFailuresSelected() async throws {
        let fixture = try makeFixture(failingIndex: 1)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchBatch(placeText: "12345", serverText: "shared-job")

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
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[0].id })?.savedServer, "shared-job")
        XCTAssertEqual(saved.first(where: { $0.id == fixture.accounts[1].id })?.savedPlaceID, "")
    }

    func testStopAllStopsEveryRunningAccount() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        fixture.store.toggleBatchGroup("Wave")
        await fixture.store.launchBatch(placeText: "12345", serverText: "")
        XCTAssertEqual(fixture.store.runningAccountIDs, Set(fixture.accounts.map(\.id)))
        XCTAssertEqual(fixture.store.launchStatus, "Running 3 accounts with unmodified Roblox")

        await fixture.store.stopAll()

        XCTAssertTrue(fixture.store.runningAccountIDs.isEmpty)
        XCTAssertEqual(fixture.store.launchStatus, "Stopped all Roblox clients")
        XCTAssertEqual(fixture.store.batchStatus, "All Roblox clients stopped")
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
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "RAMacAppTests-\(UUID().uuidString)"))
        let store = AccountStore(
            repository: repository,
            vault: vault,
            api: api,
            launcher: launcher,
            preferences: preferences,
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

    func authenticatedUser(cookie rawCookie: String) async throws -> RobloxUser {
        throw RobloxAPIError.invalidSession
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

    func maximumConcurrentTicketRequests() -> Int {
        maximumActiveTicketRequests
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

import Foundation
import RAMacCore

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

    private let repository: AccountRepository
    private let vault: any SecretVault
    private let api: any RobloxAPIProviding
    private let builder: RobloxLaunchURLBuilder
    private let launcher: any ParallelRobloxLaunching

    init(
        repository: AccountRepository = AccountRepository(),
        vault: any SecretVault = KeychainVault(),
        api: any RobloxAPIProviding = RobloxAPIClient(),
        builder: RobloxLaunchURLBuilder = RobloxLaunchURLBuilder(),
        launcher: (any ParallelRobloxLaunching)? = nil,
        launchMode: RobloxLaunchMode? = nil
    ) {
        self.repository = repository
        self.vault = vault
        self.api = api
        self.builder = builder
        self.launcher = launcher ?? ParallelRobloxLauncher()
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
            groups = ManagedAccount.normalizedGroups(
                (try repository.loadGroups()) + accounts.flatMap(\.groups)
            )
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

    func selectBatchRange(from anchorID: UUID?, to targetID: UUID, orderedAccounts: [ManagedAccount]) {
        guard !isBatchLaunching else { return }
        let eligibleAccounts = orderedAccounts.filter { !isRunning($0) }
        guard let targetIndex = eligibleAccounts.firstIndex(where: { $0.id == targetID }) else { return }
        let anchorIndex = anchorID.flatMap { anchor in
            eligibleAccounts.firstIndex(where: { $0.id == anchor })
        } ?? targetIndex
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let selectedIDs = Set(range.map { eligibleAccounts[$0].id })
        batchSelectedIDs.formUnion(selectedIDs)
        for accountID in selectedIDs { batchStates[accountID] = nil }
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
        let refreshedIDs = await launcher.runningAccountIDs(from: accounts.map(\.id))
        if refreshedIDs != runningAccountIDs {
            runningAccountIDs = refreshedIDs
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
            selectedID = accounts.first?.id
            Task { await launcher.removePreparedCopy(accountID: account.id) }
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
        guard !isRunning(account) else {
            notice = Notice(title: "Account is already running", message: RobloxLaunchError.accountAlreadyRunning.localizedDescription)
            return
        }
        guard let placeID = Int64(placeText.trimmingCharacters(in: .whitespacesAndNewlines)), placeID > 0 else {
            notice = Notice(title: "Check the place ID", message: RobloxLaunchError.invalidPlaceID.localizedDescription)
            return
        }
        isWorking = true
        launchStatus = "Requesting a launch ticket"
        defer { isWorking = false }

        do {
            guard let cookie = try vault.read(for: account.id), !cookie.isEmpty else {
                throw RobloxAPIError.invalidSession
            }
            let serverInput = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
            let target: RobloxServerTarget
            if serverInput.isEmpty {
                target = .publicServer
            } else if let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: serverInput) {
                launchStatus = "Resolving the private server"
                let accessCode = try await api.privateServerAccessCode(
                    placeID: placeID,
                    linkCode: linkCode,
                    cookie: cookie
                )
                target = .privateServer(accessCode: accessCode, linkCode: linkCode)
            } else {
                target = .job(serverInput)
            }

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
            _ = try await launcher.launch(url, for: account.id, mode: launchMode)
            await refreshRunningInstances()
            guard isRunning(account) else {
                throw launchMode == .official
                    ? RobloxLaunchError.officialParallelUnavailable
                    : RobloxLaunchError.openFailed
            }

            var updated = account
            updated.lastUsed = Date()
            updated.savedPlaceID = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.savedServer = serverInput
            update(updated)
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

        let serverInput = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
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

                        let target: RobloxServerTarget
                        if serverInput.isEmpty {
                            target = .publicServer
                        } else if let linkCode = RobloxLaunchURLBuilder.privateLinkCode(from: serverInput) {
                            let accessCode = try await api.privateServerAccessCode(
                                placeID: placeID,
                                linkCode: linkCode,
                                cookie: cookie
                            )
                            target = .privateServer(accessCode: accessCode, linkCode: linkCode)
                        } else {
                            target = .job(serverInput)
                        }

                        let ticket = try await api.authenticationTicket(cookie: cookie)
                        let url = try builder.makeURL(ticket: ticket, placeID: placeID, target: target)
                        _ = try await launcher.launch(url, for: account.id, mode: launchMode)
                        return BatchOutcome(accountID: account.id, username: account.username, errorMessage: nil)
                    } catch {
                        return BatchOutcome(
                            accountID: account.id,
                            username: account.username,
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
                errorMessage: message
            )
        }
        for outcome in outcomes where outcome.errorMessage == nil {
            if let index = accounts.firstIndex(where: { $0.id == outcome.accountID }) {
                accounts[index].lastUsed = Date()
                accounts[index].savedPlaceID = String(placeID)
                accounts[index].savedServer = serverInput
            }
        }
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

    private func batchFailureMessage(_ failures: [BatchOutcome]) -> String {
        let shown = failures.prefix(5).map { "@\($0.username): \($0.errorMessage ?? "Unknown error")" }
        let remaining = failures.count - shown.count
        if remaining > 0 {
            return (shown + ["\(remaining) more failed."]).joined(separator: "\n")
        }
        return shown.joined(separator: "\n")
    }
}

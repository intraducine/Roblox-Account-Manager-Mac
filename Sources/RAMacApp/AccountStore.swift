import Foundation
import RAMacCore

@MainActor
final class AccountStore: ObservableObject {
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var accounts: [ManagedAccount] = []
    @Published var selectedID: UUID?
    @Published var search = ""
    @Published var isWorking = false
    @Published var notice: Notice?
    @Published var launchStatus = "Ready"
    @Published private(set) var runningAccountIDs = Set<UUID>()

    private let repository: AccountRepository
    private let vault: any SecretVault
    private let api: RobloxAPIClient
    private let builder: RobloxLaunchURLBuilder
    private let launcher: ParallelRobloxLauncher

    init(
        repository: AccountRepository = AccountRepository(),
        vault: any SecretVault = KeychainVault(),
        api: RobloxAPIClient = RobloxAPIClient(),
        builder: RobloxLaunchURLBuilder = RobloxLaunchURLBuilder(),
        launcher: ParallelRobloxLauncher? = nil
    ) {
        self.repository = repository
        self.vault = vault
        self.api = api
        self.builder = builder
        self.launcher = launcher ?? ParallelRobloxLauncher()
        load()
    }

    var selectedAccount: ManagedAccount? {
        guard let selectedID else { return nil }
        return accounts.first(where: { $0.id == selectedID })
    }

    var filteredAccounts: [ManagedAccount] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = accounts.sorted {
            if $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedSame {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending
        }
        guard !needle.isEmpty else { return sorted }
        return sorted.filter {
            $0.username.localizedCaseInsensitiveContains(needle)
                || $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.alias.localizedCaseInsensitiveContains(needle)
                || $0.group.localizedCaseInsensitiveContains(needle)
        }
    }

    func load() {
        do {
            accounts = try repository.load()
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

    func refreshRunningInstances() async {
        runningAccountIDs = await launcher.runningAccountIDs(from: accounts.map(\.id))
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
                notice = Notice(title: "Account added", message: "\(user.name) is stored in this Mac's Keychain.")
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
        let cleanGroup = updated.group.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.group = cleanGroup.isEmpty ? "Default" : cleanGroup
        if updated.avatarURLString == nil {
            updated.avatarURLString = accounts[index].avatarURLString
        }
        accounts[index] = updated
        do {
            try repository.save(accounts)
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
            selectedID = accounts.first?.id
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
            launchStatus = "Preparing an isolated Roblox copy"
            _ = try await launcher.launch(url, for: account.id)
            await refreshRunningInstances()

            var updated = account
            updated.lastUsed = Date()
            updated.savedPlaceID = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.savedServer = serverInput
            update(updated)
            launchStatus = "Running @\(account.username) in parallel"
        } catch {
            launchStatus = "Launch failed"
            notice = Notice(title: "Roblox did not launch", message: error.localizedDescription)
        }
    }
}

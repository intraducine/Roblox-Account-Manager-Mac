import RAMacCore
import SwiftUI

struct JoinablePlayersView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @State private var sourceKey = "all"
    @State private var search = ""
    @State private var selectedPlayerID: Int64?
    @State private var selectedAccountIDs = Set<UUID>()
    @State private var assessments: [AccountJoinAssessment] = []
    @State private var pendingVerifiedPlayer: DiscoveredPlayer?
    @State private var pendingVerifiedAccountIDs = Set<UUID>()
    @State private var pendingVerifiedAction = "Launch Ready Accounts"
    @State private var pendingVerifiedMessage = ""
    @State private var pendingUnconfirmedPlayer: DiscoveredPlayer?
    @State private var discoveryTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if store.accounts.isEmpty {
                emptyState("Add a Roblox account before finding players.", symbol: "person.badge.plus")
            } else if store.isDiscoveringPlayers && store.discoveredPlayers.isEmpty {
                ProgressView("Checking friends in experiences")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.discoveredPlayers.isEmpty {
                emptyState(emptyMessage, symbol: "person.2.slash")
            } else {
                HSplitView {
                    playerTable.frame(minWidth: 560)
                    detail.frame(minWidth: 390, idealWidth: 450)
                }
            }
        }
        .navigationTitle("Joinable Players")
        .frame(minWidth: 1040, minHeight: 650)
        .onChange(of: selectedPlayerID) { _ in
            selectedAccountIDs.removeAll()
            assessments.removeAll()
        }
        .onChange(of: store.runningAccountIDs) { runningAccountIDs in
            selectedAccountIDs.subtract(runningAccountIDs)
            assessments.removeAll { runningAccountIDs.contains($0.accountID) }
        }
        .task {
            await store.refreshRunningInstances()
            selectedAccountIDs.subtract(store.runningAccountIDs)
        }
        .onDisappear {
            discoveryTask?.cancel()
            discoveryTask = nil
        }
        .confirmationDialog(
            "Review the account selection",
            isPresented: Binding(
                get: { pendingVerifiedPlayer != nil },
                set: { if !$0 { pendingVerifiedPlayer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingVerifiedAction) {
                guard let player = pendingVerifiedPlayer else { return }
                let accountIDs = pendingVerifiedAccountIDs
                pendingVerifiedPlayer = nil
                Task { await store.launchVerifiedPlayer(player, accountIDs: accountIDs) }
            }
            Button("Change Selection") { pendingVerifiedPlayer = nil }
            Button("Cancel", role: .cancel) { pendingVerifiedPlayer = nil }
        } message: {
            Text(pendingVerifiedMessage)
        }
        .confirmationDialog(
            "Try an unconfirmed server?",
            isPresented: Binding(
                get: { pendingUnconfirmedPlayer != nil },
                set: { if !$0 { pendingUnconfirmedPlayer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Try Selected Accounts") {
                guard let player = pendingUnconfirmedPlayer else { return }
                let accountIDs = selectedAccountIDs
                pendingUnconfirmedPlayer = nil
                Task { await store.tryUnconfirmedPlayer(player, accountIDs: accountIDs) }
            }
            Button("Cancel", role: .cancel) { pendingUnconfirmedPlayer = nil }
        } message: {
            Text("Roblox has not confirmed that this server is public. Roblox may reject some or all selected accounts. The app will not call this server private.")
        }
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $sourceKey) {
                Text("All Accounts").tag("all")
                Text("Selected Accounts").tag("selected")
                ForEach(store.groupNames, id: \.self) { Text($0).tag("group:\($0)") }
            }
            .frame(width: 220)
            TextField("Search players", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Button(store.isDiscoveringPlayers ? "Refreshing" : "Refresh") {
                startDiscovery()
            }
            .disabled(store.isDiscoveringPlayers || sourceAccounts.isEmpty)
            Spacer()
            if let updated = store.discoveryUpdatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func startDiscovery() {
        discoveryTask?.cancel()
        let accounts = sourceAccounts
        discoveryTask = Task {
            await store.discoverPlayers(sourceAccounts: accounts)
            if !Task.isCancelled { discoveryTask = nil }
        }
    }

    private var playerTable: some View {
        Table(filteredPlayers, selection: $selectedPlayerID) {
            TableColumn("Player") { player in
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.candidate.displayName).fontWeight(.medium)
                    Text(playerIdentity(player)).font(.caption).foregroundStyle(.secondary)
                }
            }
            TableColumn("Found Through") { player in
                Text(sourceNames(for: player).joined(separator: ", "))
                    .lineLimit(2)
            }
            TableColumn("Experience") { player in
                Text(player.presence.locationName ?? "Roblox experience").lineLimit(2)
            }
            TableColumn("Server") { player in
                Label(serverText(player.verification), systemImage: serverSymbol(player.verification))
                    .accessibilityLabel("Server: \(serverText(player.verification))")
            }
            TableColumn("Open Spaces") { player in
                Text(openSpacesText(player.verification))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let player = selectedPlayer {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(player.candidate.displayName).font(.title2.weight(.semibold))
                        Text(playerIdentity(player)).foregroundStyle(.secondary)
                        Text("Visible to a saved account").font(.caption).foregroundStyle(.secondary)
                    }

                    LabeledContent("Experience", value: player.presence.locationName ?? "Roblox experience")
                    LabeledContent("Found through", value: sourceNames(for: player).joined(separator: ", "))
                    LabeledContent("Server", value: serverText(player.verification))
                    LabeledContent("Open spaces", value: openSpacesText(player.verification))
                    if let explanation = verificationExplanation(player.verification) {
                        Text(explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                    Text("Managed Accounts").font(.headline)
                    AccountJoinMatrixView(
                        store: store,
                        selectedAccountIDs: $selectedAccountIDs,
                        assessments: assessments
                    )
                    Button("Check Selected Accounts") {
                        Task { assessments = await store.assessments(for: player, accountIDs: selectedAccountIDs) }
                    }
                    .disabled(selectedAccountIDs.isEmpty)

                    primaryActions(for: player)
                }
                .padding(18)
            }
        } else {
            emptyState("Select a player to review the server and choose accounts.", symbol: "cursorarrow.click")
        }
    }

    @ViewBuilder
    private func primaryActions(for player: DiscoveredPlayer) -> some View {
        switch player.verification {
        case .friendTarget:
            Button("Join Friend with \(selectedAccountIDs.count) Account\(selectedAccountIDs.count == 1 ? "" : "s")") {
                Task { await prepareFriendLaunch(player) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedAccountIDs.isEmpty || !hasSelectedSource(for: player))
            if !selectedAccountIDs.isEmpty, !hasSelectedSource(for: player) {
                Text("Select at least one account listed under Found through. That account starts first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .verifiedPublic:
            Button("Join \(selectedAccountIDs.count) Account\(selectedAccountIDs.count == 1 ? "" : "s")") {
                Task { await prepareVerifiedLaunch(player) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedAccountIDs.isEmpty)
        case .unconfirmed:
            Button("Continue Checking") { Task { await store.continueVerification(for: player) } }
                .buttonStyle(.borderedProminent)
            Button("Try Selected Accounts") { pendingUnconfirmedPlayer = player }
                .disabled(selectedAccountIDs.isEmpty)
            Button("Open Profile as Source Account") { openProfile(player) }
        case .paused:
            Button("Check Again") { Task { await store.continueVerification(for: player) } }
                .buttonStyle(.borderedProminent)
            Button("Try Selected Accounts") { pendingUnconfirmedPlayer = player }
                .disabled(selectedAccountIDs.isEmpty)
            Button("Open Profile as Source Account") { openProfile(player) }
        case .restrictedOrUnavailable, .noServerSupplied, .verificationFailed:
            Button("Open Player Profile as Source") { openProfile(player) }
                .buttonStyle(.borderedProminent)
        }
        Text("Expected does not guarantee entry. Roblox can still reject a launch because of access, capacity, age, region, or a server change.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func prepareFriendLaunch(_ player: DiscoveredPlayer) async {
        let currentAssessments = await store.assessments(for: player, accountIDs: selectedAccountIDs)
        assessments = currentAssessments
        guard currentAssessments.allSatisfy({ $0.state == .expectedToJoin }) else {
            store.notice = AccountStore.Notice(
                title: "Some accounts are not ready",
                message: "Review the status shown beside each selected account. No Roblox client was started."
            )
            return
        }
        await store.launchFriendPlayer(player, accountIDs: selectedAccountIDs)
    }

    @MainActor
    private func prepareVerifiedLaunch(_ player: DiscoveredPlayer) async {
        let currentAssessments = await store.assessments(
            for: player,
            accountIDs: selectedAccountIDs,
            refreshServer: true
        )
        assessments = currentAssessments
        let expectedIDs = Set(
            currentAssessments
                .filter { $0.state == .expectedToJoin }
                .map(\.accountID)
        )
        guard !expectedIDs.isEmpty else {
            store.notice = AccountStore.Notice(
                title: "No accounts are ready",
                message: "Review the status shown beside each selected account."
            )
            return
        }
        guard expectedIDs.count < selectedAccountIDs.count else {
            await store.launchVerifiedPlayer(player, accountIDs: expectedIDs)
            return
        }

        let noSpaceCount = currentAssessments.filter { $0.state == .serverHasNoSpace }.count
        pendingVerifiedPlayer = player
        pendingVerifiedAccountIDs = expectedIDs
        if noSpaceCount > 0 {
            pendingVerifiedAction = "Launch First \(expectedIDs.count)"
            pendingVerifiedMessage = "The last server update has space for \(expectedIDs.count) of the \(selectedAccountIDs.count) selected accounts. Capacity can change during launch."
        } else {
            pendingVerifiedAction = "Launch \(expectedIDs.count) Ready Account\(expectedIDs.count == 1 ? "" : "s")"
            pendingVerifiedMessage = "Only \(expectedIDs.count) of the \(selectedAccountIDs.count) selected accounts are ready. Review the status shown beside each account."
        }
    }

    private var sourceAccounts: [ManagedAccount] {
        if sourceKey == "selected" {
            return store.accounts.filter { store.batchSelectedIDs.contains($0.id) }
        }
        if sourceKey.hasPrefix("group:") {
            let group = String(sourceKey.dropFirst("group:".count))
            return store.accounts.filter { $0.belongs(to: group) }
        }
        return store.accounts
    }

    private var filteredPlayers: [DiscoveredPlayer] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let runningUserIDs = Set(store.accounts.filter { store.runningAccountIDs.contains($0.id) }.map(\.userID))
        return store.discoveredPlayers.filter { player in
            needle.isEmpty
                || player.candidate.username.localizedCaseInsensitiveContains(needle)
                || player.candidate.displayName.localizedCaseInsensitiveContains(needle)
                || String(player.candidate.userID).contains(needle)
                || (player.presence.locationName?.localizedCaseInsensitiveContains(needle) ?? false)
        }.sorted { left, right in
            let leftRunning = runningUserIDs.contains(left.id)
            let rightRunning = runningUserIDs.contains(right.id)
            if leftRunning != rightRunning { return leftRunning }
            return left.candidate.displayName.localizedCaseInsensitiveCompare(right.candidate.displayName) == .orderedAscending
        }
    }

    private var selectedPlayer: DiscoveredPlayer? {
        guard let selectedPlayerID else { return nil }
        return store.discoveredPlayers.first(where: { $0.id == selectedPlayerID })
    }

    private var emptyMessage: String {
        if store.accountHealth.values.allSatisfy({ !$0.isReady }) && store.discoveryUpdatedAt != nil {
            return "Sign in to at least one account before checking its friends."
        }
        if let failure = store.discoveryFailures.first { return failure.message }
        return store.discoveryUpdatedAt == nil
            ? "Choose a source and select Refresh."
            : "Roblox did not return any friends in a visible experience."
    }

    private func sourceNames(for player: DiscoveredPlayer) -> [String] {
        player.candidate.sourceAccountIDs.compactMap { id in
            store.accounts.first(where: { $0.id == id }).map { "@\($0.username)" }
        }.sorted()
    }

    private func hasSelectedSource(for player: DiscoveredPlayer) -> Bool {
        !selectedAccountIDs.isDisjoint(with: player.candidate.sourceAccountIDs)
    }

    private func playerIdentity(_ player: DiscoveredPlayer) -> String {
        let username = player.candidate.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "User ID \(player.candidate.userID)" : "@\(username)"
    }

    private func openProfile(_ player: DiscoveredPlayer) {
        Task {
            guard let sourceID = await store.readyWebsiteAccount(
                from: player.candidate.sourceAccountIDs
            ) else { return }
            openWindow(value: AccountWebsiteRequest(
                accountID: sourceID,
                destination: .playerProfile(player.candidate.userID)
            ))
        }
    }

    private func serverText(_ verification: PublicServerVerification) -> String {
        switch verification {
        case .friendTarget: return "Friend server"
        case .verifiedPublic(let server): return server.openSpaces == 0 ? "Public, full" : "Public"
        case .unconfirmed: return "Not confirmed"
        case .paused: return "Check paused"
        case .restrictedOrUnavailable: return "Restricted or unavailable"
        case .noServerSupplied: return "No server supplied"
        case .verificationFailed: return "Could not verify"
        }
    }

    private func serverSymbol(_ verification: PublicServerVerification) -> String {
        switch verification {
        case .friendTarget: return "person.2"
        case .verifiedPublic: return "checkmark.circle"
        case .unconfirmed: return "questionmark.circle"
        case .paused: return "clock"
        case .restrictedOrUnavailable: return "lock"
        case .noServerSupplied: return "minus.circle"
        case .verificationFailed: return "exclamationmark.triangle"
        }
    }

    private func openSpacesText(_ verification: PublicServerVerification) -> String {
        if case .verifiedPublic(let server) = verification { return String(server.openSpaces) }
        return "Unknown"
    }

    private func verificationExplanation(_ verification: PublicServerVerification) -> String? {
        switch verification {
        case .friendTarget:
            return "One selected friend account starts first. The manager then gives the same reported Job ID to the other selected accounts. Roblox checks access and space for each account. This does not search public server pages."
        case .verifiedPublic:
            return "The reported Job ID appears in Roblox's public server list."
        case .unconfirmed(let pagesSearched):
            return "Checked \(pagesSearched) public server page\(pagesSearched == 1 ? "" : "s"). Continue checking before you treat this server as public."
        case .paused(let pagesSearched, let retryAfter):
            let wait: String
            if let retryAfter {
                wait = " Try again in \(retryAfter) second\(retryAfter == 1 ? "" : "s")."
            } else {
                wait = " Try again in a minute."
            }
            if pagesSearched == 0 {
                return "No server pages were checked for this player. The app paused before another request could exceed Roblox's limit.\(wait)"
            }
            return "Checked \(pagesSearched) public server page\(pagesSearched == 1 ? "" : "s"). The app paused before another request could exceed Roblox's limit.\(wait)"
        case .restrictedOrUnavailable:
            return "The complete public search did not find this server. Open the selected-account website and use the Join button there. The manager will start that account."
        case .noServerSupplied:
            return "Roblox showed an experience but did not give this app a server target."
        case .verificationFailed(let message):
            return message
        }
    }

    private func emptyState(_ message: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct AccountJoinMatrixView: View {
    @ObservedObject var store: AccountStore
    @Binding var selectedAccountIDs: Set<UUID>
    let assessments: [AccountJoinAssessment]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(store.accounts) { account in
                let isRunning = store.runningAccountIDs.contains(account.id)
                HStack(spacing: 8) {
                    Toggle(
                        "Select @\(account.username)",
                        isOn: Binding(
                            get: { selectedAccountIDs.contains(account.id) },
                            set: { selected in
                                guard !isRunning else {
                                    selectedAccountIDs.remove(account.id)
                                    return
                                }
                                if selected { selectedAccountIDs.insert(account.id) }
                                else { selectedAccountIDs.remove(account.id) }
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(isRunning)
                    Text(account.title).lineLimit(1)
                    Spacer()
                    Text(assessmentText(account.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func assessmentText(_ accountID: UUID) -> String {
        if store.runningAccountIDs.contains(accountID) {
            return "Already running"
        }
        guard let assessment = assessments.first(where: { $0.accountID == accountID }) else {
            return "Not checked"
        }
        switch assessment.state {
        case .expectedToJoin: return "Expected to join"
        case .alreadyRunning: return "Already running"
        case .signedOut: return "Signed out"
        case .serverHasNoSpace: return "No server space"
        case .statusUnknown: return "Status unknown"
        }
    }
}

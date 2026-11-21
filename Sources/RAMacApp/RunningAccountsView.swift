import RAMacCore
import SwiftUI

struct RunningAccountsView: View {
    @ObservedObject var store: AccountStore
    @State private var showsLastSession = false
    @State private var showsSaveLayout = false
    @State private var layoutName = ""
    @State private var layoutToRemove: NamedWindowLayout?

    var body: some View {
        List {
            Section("Running") {
                if runningAccounts.isEmpty {
                    Text("No Roblox accounts are running.").foregroundStyle(.secondary)
                }
                ForEach(runningAccounts) { account in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.title).fontWeight(.medium)
                            Text(launchTarget(for: account)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Bring to Front") { Task { await store.bringToFront(account) } }
                            .accessibilityLabel("Bring Roblox for @\(account.username) to front")
                        Button("Stop", role: .destructive) { Task { await store.stop(account) } }
                            .accessibilityLabel("Stop Roblox for @\(account.username)")
                            .disabled(store.isBusyWithRoblox)
                    }
                    .padding(.vertical, 4)
                }
            }
            if !sessionAccounts.isEmpty {
                Section("Last Session") {
                    Button("Review Last Session…") { showsLastSession = true }
                        .disabled(store.isBusyWithRoblox)
                }
            }
            if !runningAccounts.isEmpty || !store.namedWindowLayouts.isEmpty {
                Section("Window Layouts") {
                    if !runningAccounts.isEmpty {
                        Button("Save Current Window Layout…") {
                            layoutName = ""
                            showsSaveLayout = true
                        }
                        .disabled(store.isBusyWithRoblox)
                    }
                    ForEach(store.namedWindowLayouts) { layout in
                        HStack {
                            Text(layout.name)
                            Spacer()
                            Button("Apply") { Task { await store.applyWindowLayout(layout) } }
                                .accessibilityLabel("Apply \(layout.name)")
                                .disabled(store.isBusyWithRoblox || !layout.assignments.contains {
                                    store.runningAccountIDs.contains($0.accountID)
                                })
                            Menu {
                                Button("Delete Layout", role: .destructive) { layoutToRemove = layout }
                            } label: {
                                Label("Options for \(layout.name)", systemImage: "ellipsis")
                                    .labelStyle(.iconOnly)
                            }
                            .menuIndicator(.hidden)
                        }
                    }
                }
            }
            if !batchAccounts.isEmpty {
                Section("Last Batch") {
                    ForEach(batchAccounts) { account in
                        if let result = store.lastBatchResults[account.id] {
                            if result.healthMessage != nil {
                                BatchAccountIssueRow(store: store, account: account)
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.title).fontWeight(.medium)
                                    Text(result.errorMessage ?? result.label).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !store.batchReadyIDs.isEmpty {
                        BatchReadinessView(store: store)
                    } else if store.canRetryLastBatch {
                        Button(store.lastBatchResults.values.contains(.started) ? "Retry Failed Accounts" : "Retry Batch") {
                            Task { await store.retryLastBatch() }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .buttonStyle(.bordered)
        .frame(minWidth: 540, minHeight: 280)
        .robloxUpdateRecovery(store)
        .sheet(isPresented: $showsLastSession) {
            LastSessionView(store: store, records: sessionAccounts)
        }
        .sheet(isPresented: $showsSaveLayout) { saveLayoutSheet }
        .confirmationDialog(
            "Delete \(layoutToRemove?.name ?? "this layout")?",
            isPresented: Binding(
                get: { layoutToRemove != nil },
                set: { if !$0 { layoutToRemove = nil } }
            )
        ) {
            Button("Delete Layout", role: .destructive) {
                if let layout = layoutToRemove { store.removeWindowLayout(layout) }
                layoutToRemove = nil
            }
            Button("Cancel", role: .cancel) { layoutToRemove = nil }
        }
        .task {
            while !Task.isCancelled {
                await store.pollRunningAccounts()
                do { try await Task.sleep(for: .seconds(3)) }
                catch { return }
            }
        }
    }

    private var runningAccounts: [ManagedAccount] {
        store.accounts.filter { store.runningAccountIDs.contains($0.id) }
    }

    private var batchAccounts: [ManagedAccount] {
        store.accounts.filter { store.lastBatchResults[$0.id] != nil }
    }

    private var sessionAccounts: [SessionLaunch] {
        store.lastSession.filter { record in store.accounts.contains { $0.id == record.accountID } }
    }

    private var saveLayoutSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Window Layout").font(.headline)
            TextField("Name", text: $layoutName)
            HStack {
                Spacer()
                Button("Cancel") { showsSaveLayout = false }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if await store.captureWindowLayout(name: layoutName) { showsSaveLayout = false }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusyWithRoblox)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func launchTarget(for account: ManagedAccount) -> String {
        guard let target = store.activeLaunchTargets[account.id] else { return "Roblox app" }
        let game = store.experiences.first { $0.placeID == target.placeID }?.experienceName
            ?? "Place \(target.placeID)"
        return target.targetKind == .privateServer ? "Launched \(game) · Private server" : "Launched \(game)"
    }
}

private struct LastSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    let records: [SessionLaunch]
    @State private var selectedIDs = Set<UUID>()
    @State private var useAnotherPublicServer = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resume Last Session").font(.headline)
            List(records) { record in
                if let account = store.accounts.first(where: { $0.id == record.accountID }) {
                    let isRunning = store.runningAccountIDs.contains(account.id)
                    HStack {
                        Toggle("@\(account.username)", isOn: Binding(
                            get: { !isRunning && selectedIDs.contains(account.id) },
                            set: { if $0 { selectedIDs.insert(account.id) } else { selectedIDs.remove(account.id) } }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(isRunning)
                        Spacer(minLength: 16)
                        Text(isRunning ? "Already running" : destinationName(record))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if records.contains(where: { $0.publicJobID != nil }) {
                Toggle("Use another public server if the last one is unavailable", isOn: $useAnotherPublicServer)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Resume Selected") {
                    let ids = selectedIDs.subtracting(store.runningAccountIDs)
                    let fallback = useAnotherPublicServer
                    dismiss()
                    Task { await store.resumeLastSession(accountIDs: ids, useAnotherPublicServer: fallback) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isSubset(of: store.runningAccountIDs) || store.isBusyWithRoblox)
            }
        }
        .padding(20)
        .frame(width: 530, height: 330)
        .onAppear { selectedIDs = Set(records.map(\.accountID)).subtracting(store.runningAccountIDs) }
    }

    private func destinationName(_ record: SessionLaunch) -> String {
        guard let placeID = record.placeID else { return "Roblox app" }
        let game = store.experiences.first { $0.placeID == placeID }?.experienceName ?? "Place \(placeID)"
        return record.usesPrivateServer ? "\(game) · Private server" : game
    }
}

struct BatchAccountIssueRow: View {
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    @State private var showsSignIn = false

    var body: some View {
        let health = store.accountHealth[account.id] ?? .unchecked
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.title).fontWeight(.medium)
                Text(health.launchIssue).foregroundStyle(.secondary)
            }
            Spacer()
            if health.needsSignIn {
                Button("Sign In Again") { showsSignIn = true }
                    .accessibilityLabel("Sign in again as @\(account.username)")
            } else if !health.isReady {
                Button("Retry Check") { Task { await store.checkAccount(account) } }
                    .accessibilityLabel("Retry sign-in check for @\(account.username)")
                    .disabled(health == .checking)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            AccountReauthenticationView(store: store, account: account)
        }
    }
}

extension View {
    func robloxUpdateRecovery(_ store: AccountStore) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            RobloxUpdateRecoveryView(store: store)
        }
    }
}

private struct RobloxUpdateRecoveryView: View {
    @ObservedObject var store: AccountStore

    var body: some View {
        if let recovery = store.robloxUpdateRecovery {
            VStack(alignment: .leading, spacing: 8) {
                Text("Roblox Update").font(.headline)
                switch recovery {
                case .waiting(let message, let canOpenUpdater):
                    Text(message).foregroundStyle(.secondary)
                    HStack {
                        Button("Dismiss") { store.cancelRobloxUpdateRecovery() }
                        Spacer()
                        if canOpenUpdater {
                            Button("Open Roblox Updater") { Task { await store.checkRobloxUpdate(openUpdater: true) } }
                        }
                        Button("Check Roblox Version") { Task { await store.checkRobloxUpdate() } }
                    }
                case .checking:
                    ProgressView("Checking Roblox version…").controlSize(.small)
                case .ready:
                    HStack {
                        Text("Roblox is up to date.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") { store.cancelRobloxUpdateRecovery() }
                        Button("Retry Launch") { Task { await store.retryAfterRobloxUpdate() } }
                            .disabled(store.isBusyWithRoblox)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

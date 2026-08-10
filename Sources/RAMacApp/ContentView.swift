import RAMacCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AccountStore
    @State private var showsAddAccount = false
    @State private var showsLicense = false
    @State private var pendingRemoval: ManagedAccount?
    @State private var batchPlaceID = ""
    @State private var batchServer = ""

    var body: some View {
        NavigationSplitView {
            accountSidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let account = store.selectedAccount {
                VStack(spacing: 0) {
                    AccountDetailView(
                        store: store,
                        account: account,
                        showsLaunchBar: store.batchSelectedIDs.isEmpty
                    )
                    .id(account.id)

                    if !store.batchSelectedIDs.isEmpty {
                        BatchLaunchBar(
                            store: store,
                            placeID: $batchPlaceID,
                            server: $batchServer
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    showsLicense = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showsAddAccount) {
            AddAccountView(store: store)
        }
        .sheet(isPresented: $showsLicense) {
            LicenseNoticeView()
        }
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.title ?? "this account")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("Remove Account", role: .destructive) {
                if let pendingRemoval { store.remove(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes the account metadata and its Keychain session from this Mac.")
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshRunningInstances() }
        }
        .onChange(of: store.batchSelectedIDs) { selectedIDs in
            guard !selectedIDs.isEmpty,
                  batchPlaceID.isEmpty,
                  let selectedAccount = store.selectedAccount else { return }
            batchPlaceID = selectedAccount.savedPlaceID
            batchServer = selectedAccount.savedServer
        }
    }

    private var accountSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedID) {
                ForEach(groupNames, id: \.self) { group in
                    Section(group) {
                        ForEach(accounts(in: group)) { account in
                            AccountRow(
                                account: account,
                                isRunning: store.isRunning(account),
                                isBatchSelected: store.isBatchSelected(account),
                                batchState: store.batchStates[account.id],
                                isSelectionDisabled: store.isBatchLaunching,
                                onToggleBatch: { store.toggleBatchSelection(account) }
                            )
                            .tag(account.id)
                            .contextMenu {
                                Button("Remove Account", role: .destructive) {
                                    pendingRemoval = account
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            sidebarStatus
        }
        .navigationTitle("Accounts")
        .searchable(text: $store.search, placement: .sidebar, prompt: "Search accounts")
    }

    private var sidebarStatus: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Text(store.batchSelectedIDs.isEmpty
                     ? "Batch selection"
                     : "\(store.batchSelectedIDs.count) selected")
                    .fontWeight(.medium)
                Spacer()
                Menu("Groups") {
                    ForEach(groupNames, id: \.self) { group in
                        Button(store.isBatchGroupSelected(group) ? "Clear \(group)" : "Select \(group)") {
                            store.toggleBatchGroup(group)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.isBatchLaunching)

                if !store.batchSelectedIDs.isEmpty {
                    Button("Clear") { store.clearBatchSelection() }
                        .buttonStyle(.plain)
                        .disabled(store.isBatchLaunching)
                }
            }

            HStack {
                Text("\(store.runningAccountIDs.count) running")
                Spacer()
                Text("\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")")
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var groupNames: [String] {
        Array(Set(store.filteredAccounts.map(\.group))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func accounts(in group: String) -> [ManagedAccount] {
        store.filteredAccounts.filter { $0.group == group }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No Accounts")
                .font(.title2.weight(.semibold))
            Text("Add a Roblox account to launch and manage it from this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Account") { showsAddAccount = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: 360)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AccountRow: View {
    let account: ManagedAccount
    let isRunning: Bool
    let isBatchSelected: Bool
    let batchState: AccountStore.BatchLaunchState?
    let isSelectionDisabled: Bool
    let onToggleBatch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Toggle(
                "Select @\(account.username) for batch launch",
                isOn: Binding(
                    get: { isBatchSelected },
                    set: { _ in onToggleBatch() }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(isRunning || isSelectionDisabled)

            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    Image(systemName: "person.crop.square.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(account.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("@\(account.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if let batchState {
                Text(batchState.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(batchState.errorMessage == nil ? Color.secondary : Color.red)
                    .help(batchState.errorMessage ?? "Preparing this account")
            } else if isRunning {
                Text("Running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

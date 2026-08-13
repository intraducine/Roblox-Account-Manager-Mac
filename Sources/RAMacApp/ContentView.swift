import AppKit
import RAMacCore
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @ObservedObject var updater: SoftwareUpdateController
    @State private var showsLicense = false
    @State private var pendingRemoval: ManagedAccount?
    @State private var batchPlaceID = ""
    @State private var batchServerSelection = RobloxServerSelection.automatic
    @State private var showsFallbackWarning = false
    @State private var showsNewGroup = false
    @State private var newGroupName = ""
    @State private var newGroupAccountID: UUID?
    @State private var selectedGroupFilter: String?
    @State private var pendingGroupDeletion: String?

    var body: some View {
        NavigationSplitView {
            accountSidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if !store.batchSelectedIDs.isEmpty {
                BatchLaunchBar(
                    store: store,
                    placeID: $batchPlaceID,
                    serverSelection: $batchServerSelection,
                    onRequestModifiedFallback: { showsFallbackWarning = true }
                )
            } else if let account = store.selectedAccount {
                AccountDetailView(
                    store: store,
                    account: account,
                    onRequestModifiedFallback: { showsFallbackWarning = true }
                )
                .id(account.id)
            } else {
                emptyState
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openWindow(id: "joinable-players")
                } label: {
                    Label("Find Players", systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("Find players that your saved accounts can join")

                Button {
                    openWindow(id: "launch-sets")
                } label: {
                    Label("Launch Sets", systemImage: "square.stack.3d.up")
                        .labelStyle(.titleAndIcon)
                }
                .help("Open saved account and game combinations")

                Menu {
                    Button("Diagnostics and Backup") { openWindow(id: "diagnostics") }
                    Divider()
                    Button("About") { showsLicense = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsLicense) {
            LicenseNoticeView(updater: updater)
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
            Text("This removes the saved account details and Roblox sign-in from this Mac.")
        }
        .confirmationDialog(
            "Use the advanced fallback?",
            isPresented: $showsFallbackWarning
        ) {
            Button("Use Advanced Fallback", role: .destructive) {
                store.setLaunchMode(.modifiedParallel)
            }
            Button("Keep Recommended Method", role: .cancel) {}
        } message: {
            Text("This option changes each Roblox app copy so macOS can open it separately. Roblox does not allow modified clients and may restrict accounts that use them. The app never turns this option on by itself.")
        }
        .confirmationDialog(
            "Delete \(pendingGroupDeletion ?? "this group")?",
            isPresented: Binding(
                get: { pendingGroupDeletion != nil },
                set: { if !$0 { pendingGroupDeletion = nil } }
            )
        ) {
            Button("Delete Group", role: .destructive) {
                if let pendingGroupDeletion {
                    store.deleteGroup(pendingGroupDeletion)
                }
                pendingGroupDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingGroupDeletion = nil }
        } message: {
            Text("The accounts will stay saved. This only removes the group name from the accounts and Launch Sets that use it.")
        }
        .sheet(isPresented: $showsNewGroup) {
            NewGroupSheet(
                name: $newGroupName,
                message: newGroupAccountID == nil
                    ? "Create a group. You can add each account to one or more groups."
                    : "Create a group and add this account to it.",
                onCreate: {
                    _ = store.createGroup(newGroupName, addingTo: newGroupAccountID)
                    newGroupName = ""
                    newGroupAccountID = nil
                    showsNewGroup = false
                },
                onCancel: {
                    newGroupName = ""
                    newGroupAccountID = nil
                    showsNewGroup = false
                }
            )
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshRunningInstances() }
        }
        .onChange(of: store.batchSelectedIDs) { selectedIDs in
            guard !selectedIDs.isEmpty,
                  batchPlaceID.isEmpty,
                  let selectedAccount = store.selectedAccount else { return }
            batchPlaceID = selectedAccount.savedPlaceID
            batchServerSelection = .savedValue(selectedAccount.savedServer)
        }
        .onChange(of: store.groupNames) { groupNames in
            if let selectedGroupFilter,
               !groupNames.contains(where: { $0.caseInsensitiveCompare(selectedGroupFilter) == .orderedSame }) {
                self.selectedGroupFilter = nil
            }
        }
    }

    @ViewBuilder
    private var accountSidebar: some View {
        if store.accounts.isEmpty {
            accountSidebarContents
                .navigationTitle("Accounts")
        } else {
            accountSidebarContents
                .navigationTitle("Accounts")
                .searchable(text: $store.search, placement: .sidebar, prompt: "Search accounts")
        }
    }

    private var accountSidebarContents: some View {
        VStack(spacing: 0) {
            if !store.accounts.isEmpty {
                groupFilterBar
            }

            List(selection: $store.selectedID) {
                ForEach(visibleAccounts) { account in
                    AccountRow(
                        account: account,
                        isRunning: store.isRunning(account),
                        isBatchSelected: store.isBatchSelected(account),
                        batchState: store.batchStates[account.id],
                        showsBatchSelection: true,
                        isSelectionDisabled: store.isBatchLaunching || store.isOpeningSelectedApps,
                        onToggleBatch: {
                            store.toggleBatchSelection(account)
                        }
                    )
                    .tag(account.id)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().modifiers(.shift).onEnded {
                            store.toggleBatchSelection(account)
                        }
                    )
                    .contextMenu {
                        Button("Open Roblox App") {
                            Task { await store.launchApp(account: account) }
                        }
                        .disabled(
                            store.isRunning(account)
                                || store.isOpeningApp(account)
                                || store.isWorking
                                || store.isBatchLaunching
                                || store.isOpeningSelectedApps
                        )
                        Menu("Open Roblox Website") {
                            Button("Home") { openWebsite(account, .home) }
                            Button("My Profile") { openWebsite(account, .profile) }
                            Button("Settings") { openWebsite(account, .settings) }
                            Button("Security") { openWebsite(account, .security) }
                        }
                        Menu("Groups") {
                            ForEach(store.groupNames, id: \.self) { group in
                                Toggle(
                                    group,
                                    isOn: Binding(
                                        get: { account.belongs(to: group) },
                                        set: { isMember in
                                            store.setMembership(of: account, in: group, isMember: isMember)
                                        }
                                    )
                                )
                            }
                            Divider()
                            Button("New Group…") { beginNewGroup(for: account.id) }
                        }
                        Button("Remove Account", role: .destructive) {
                            pendingRemoval = account
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            if !store.accounts.isEmpty {
                sidebarStatus
            }
        }
    }

    private var groupFilterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    selectedGroupFilter = nil
                } label: {
                    Label("All Accounts", systemImage: selectedGroupFilter == nil ? "checkmark" : "person.2")
                }
                ForEach(store.groupNames, id: \.self) { group in
                    Button {
                        selectedGroupFilter = group
                    } label: {
                        Label(
                            group,
                            systemImage: selectedGroupFilter == group ? "checkmark" : "folder"
                        )
                    }
                }
                Divider()
                Button("New Group…") { beginNewGroup(for: nil) }
                if !store.groupNames.isEmpty {
                    Menu("Delete Group") {
                        ForEach(store.groupNames, id: \.self) { group in
                            Button(group, role: .destructive) {
                                pendingGroupDeletion = group
                            }
                        }
                    }
                }
            } label: {
                Label(selectedGroupFilter ?? "All Accounts", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sidebarStatus: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(store.batchSelectedIDs.isEmpty
                     ? "Select accounts to open together"
                     : "\(store.batchSelectedIDs.count) selected")
                    .foregroundStyle(store.batchSelectedIDs.isEmpty ? .secondary : .primary)
                    .fontWeight(store.batchSelectedIDs.isEmpty ? .regular : .medium)
                Spacer()
                if !store.batchSelectedIDs.isEmpty {
                    Button("Clear") { store.clearBatchSelection() }
                        .disabled(store.isBatchLaunching || store.isOpeningSelectedApps)
                }
            }

            HStack(spacing: 10) {
                Menu("Select Group") {
                    ForEach(store.groupNames, id: \.self) { group in
                        Button(store.isBatchGroupSelected(group) ? "Clear \(group)" : "Select \(group)") {
                            store.toggleBatchGroup(group)
                        }
                    }
                }
                .disabled(store.isBatchLaunching || store.isOpeningSelectedApps || store.groupNames.isEmpty)

                Spacer()

                Button("Add Account", systemImage: "plus") {
                    openWindow(id: "add-account")
                }
                .disabled(store.isWorking || store.isBatchLaunching || store.isOpeningSelectedApps)
            }

            if !store.runningAccountIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("\(store.runningAccountIDs.count) running")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(store.isStoppingAll ? "Stopping" : "Stop All", role: .destructive) {
                        Task { await store.stopAll() }
                    }
                    .disabled(
                        store.isWorking
                            || store.isBatchLaunching
                            || !store.appOpeningAccountIDs.isEmpty
                    )
                    .help("Stop every Roblox client started by this manager")
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var visibleAccounts: [ManagedAccount] {
        guard let selectedGroupFilter else { return store.filteredAccounts }
        return store.filteredAccounts.filter { $0.belongs(to: selectedGroupFilter) }
    }

    private func beginNewGroup(for accountID: UUID?) {
        newGroupName = ""
        newGroupAccountID = accountID
        showsNewGroup = true
    }

    private func openWebsite(_ account: ManagedAccount, _ destination: AccountWebsiteDestination) {
        Task {
            guard await store.prepareWebsiteSession(accountID: account.id) else { return }
            openWindow(value: AccountWebsiteRequest(accountID: account.id, destination: destination))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No Accounts")
                .font(.title2.weight(.semibold))
            Text("Add the Roblox accounts that you want to run together. You will sign in on Roblox, and this app will not save your password.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Account") { openWindow(id: "add-account") }
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
    let showsBatchSelection: Bool
    let isSelectionDisabled: Bool
    let onToggleBatch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if showsBatchSelection {
                Toggle(
                    "Select @\(account.username) for batch launch",
                    isOn: Binding(
                        get: { isBatchSelected },
                        set: { _ in
                            guard !NSEvent.modifierFlags.contains(.shift) else { return }
                            onToggleBatch()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(isRunning || isSelectionDisabled)
            }

            AccountAvatarView(url: account.avatarURL, size: 34, cornerRadius: 7)

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

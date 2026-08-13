import RAMacCore
import SwiftUI

struct AccountDetailView: View {
    private enum ProfileField: Hashable {
        case alias
        case notes
    }

    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    let showsLaunchBar: Bool
    let onRequestModifiedFallback: () -> Void
    @State private var draft: ManagedAccount
    @State private var placeID: String
    @State private var serverSelection: RobloxServerSelection
    @State private var showsAccountSettings = false
    @State private var showsNewGroup = false
    @State private var newGroupName = ""
    @State private var pendingGroupDeletion: String?
    @FocusState private var focusedProfileField: ProfileField?

    init(
        store: AccountStore,
        account: ManagedAccount,
        showsLaunchBar: Bool = true,
        onRequestModifiedFallback: @escaping () -> Void = {}
    ) {
        self.store = store
        self.account = account
        self.showsLaunchBar = showsLaunchBar
        self.onRequestModifiedFallback = onRequestModifiedFallback
        _draft = State(initialValue: account)
        _placeID = State(initialValue: account.savedPlaceID)
        _serverSelection = State(initialValue: .savedValue(account.savedServer))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    identityHeader
                        .padding(8)
                }

                if showsLaunchBar {
                    launchGroup
                }

                accountGroup
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .navigationTitle(draft.title)
        .sheet(isPresented: $showsAccountSettings) {
            accountSettings
        }
        .sheet(isPresented: $showsNewGroup) {
            NewGroupSheet(
                name: $newGroupName,
                message: "Create a group and add this account to it. Select Save Profile to keep the membership.",
                onCreate: {
                    if let group = store.createGroup(newGroupName) {
                        setDraftMembership(group, isMember: true)
                    }
                    newGroupName = ""
                    showsNewGroup = false
                },
                onCancel: {
                    newGroupName = ""
                    showsNewGroup = false
                }
            )
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
        .onChange(of: account.savedServer) { savedServer in
            serverSelection = .savedValue(savedServer)
        }
        .onChange(of: account) { updatedAccount in
            draft = updatedAccount
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedProfileField = nil
            }
        }
    }

    private var launchGroup: some View {
        GroupBox {
            VStack(spacing: 0) {
                openAppRow
                    .padding(.vertical, 8)

                Divider()

                HStack {
                    Text("Game")
                    Spacer(minLength: 24)
                    ExperienceChooserButton(store: store, placeID: gamePlaceID)
                        .disabled(store.isRunning(account))
                }
                .padding(.vertical, 8)

                Divider()

                HStack {
                    Text("Server")
                    Spacer(minLength: 24)
                    ServerSelectionControl(
                        store: store,
                        placeID: $placeID,
                        selection: $serverSelection,
                        requiredSpaces: 1
                    )
                    .disabled(store.isRunning(account))
                }
                .padding(.vertical, 8)

                Divider()

                launchActionRow
                    .padding(.vertical, 8)

                if store.launchMode == .modifiedParallel {
                    Divider()

                    LaunchClientNotice(
                        store: store,
                        onRequestModifiedFallback: onRequestModifiedFallback
                    )
                    .padding(.vertical, 8)
                }

                Divider()

                AdvancedLaunchOptions(
                    store: store,
                    placeID: gamePlaceID,
                    onRequestModifiedFallback: onRequestModifiedFallback
                )
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 4)
        } label: {
            Text("Open Roblox")
                .font(.headline)
        }
    }

    private var accountGroup: some View {
        GroupBox {
            VStack(spacing: 0) {
                AccountHealthRow(store: store, account: account)
                    .padding(.top, 2)
                    .padding(.bottom, 8)

                Divider()

                HStack {
                    Text("Alias")
                    Spacer(minLength: 24)
                    TextField("Name shown in the sidebar", text: $draft.alias)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .focused($focusedProfileField, equals: .alias)
                }
                .padding(.vertical, 8)

                Divider()

                HStack {
                    Text("Groups")
                    Spacer(minLength: 24)
                    Menu {
                        if store.groupNames.isEmpty {
                            Text("No groups created")
                        } else {
                            ForEach(store.groupNames, id: \.self) { group in
                                Toggle(
                                    group,
                                    isOn: Binding(
                                        get: { draft.belongs(to: group) },
                                        set: { isMember in setDraftMembership(group, isMember: isMember) }
                                    )
                                )
                            }
                        }
                        Divider()
                        Button("New Group…") {
                            newGroupName = ""
                            showsNewGroup = true
                        }
                        groupDeletionMenu
                    } label: {
                        Text(groupSummary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 360, alignment: .trailing)
                }
                .padding(.vertical, 8)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .focused($focusedProfileField, equals: .notes)
                        if draft.notes.isEmpty {
                            Text("Add details for this account")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 76, maxHeight: 110)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Notes are encrypted in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)

                Divider()

                HStack {
                    Menu("Open Roblox Website") {
                        Button("Home") { openWebsite(.home) }
                        Button("My Profile") { openWebsite(.profile) }
                        Button("Settings") { openWebsite(.settings) }
                        Button("Security") { openWebsite(.security) }
                    }
                    Button("Account Details…") { showsAccountSettings = true }
                    Spacer()
                    Button("Save Profile") { store.update(draft) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!profileHasChanges)
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 4)
        } label: {
            Text("Account")
                .font(.headline)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            AccountAvatarView(url: account.avatarURL, size: 68, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text("@\(draft.username)")
                    .foregroundStyle(.secondary)
                if store.isRunning(account) {
                    Label("Roblox is running", systemImage: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let lastUsed = draft.lastUsed {
                    Text("Last launched \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not launched from this Mac yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var openAppRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open the app only")
                    .fontWeight(.medium)
                Text("Open this account without joining a game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.isOpeningApp(account) ? "Opening Roblox" : "Open Roblox App") {
                Task { await store.launchApp(account: draft) }
            }
            .disabled(
                store.isWorking
                    || store.isBatchLaunching
                    || store.isOpeningSelectedApps
                    || store.isRunning(account)
                    || store.isOpeningApp(account)
            )
        }
    }

    private var launchActionRow: some View {
        HStack {
            Text(launchSummary)
                .foregroundStyle(.secondary)
            Spacer()
            if store.isRunning(account) {
                Button(store.isWorking ? "Stopping" : "Stop Roblox", role: .destructive) {
                    Task { await store.stop(account) }
                }
                .disabled(store.isWorking)
            } else {
                Button(store.isWorking ? "Launching" : "Launch Game") {
                    Task { await store.launch(account: draft, placeText: placeID, server: serverSelection) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking || numericPlaceID == nil)
            }
        }
    }

    private var accountSettings: some View {
        NavigationStack {
            Form {
                Section("Roblox Account") {
                    LabeledContent("Display name", value: draft.displayName)
                    LabeledContent("Roblox username", value: "@\(draft.username)")
                    LabeledContent("Roblox user ID", value: String(draft.userID))
                }

                Section("Saved on This Mac") {
                    LabeledContent("Alias", value: draft.alias.isEmpty ? "None" : draft.alias)
                    LabeledContent("Groups", value: groupSummary)
                    Text("Profile notes and Roblox sessions use separate encrypted macOS Keychain items.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Account Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsAccountSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560, height: 400)
    }

    private var profileHasChanges: Bool {
        draft.alias != account.alias
            || draft.groups != account.groups
            || draft.notes != account.notes
    }

    private var groupSummary: String {
        draft.groups.isEmpty ? "No groups" : draft.groups.joined(separator: ", ")
    }

    @ViewBuilder
    private var groupDeletionMenu: some View {
        if !store.groupNames.isEmpty {
            Menu("Delete Group") {
                ForEach(store.groupNames, id: \.self) { group in
                    Button(group, role: .destructive) {
                        pendingGroupDeletion = group
                    }
                }
            }
        }
    }

    private var launchSummary: String {
        if numericPlaceID == nil {
            return "Choose a game to continue"
        }
        if store.isWorking || store.isOpeningApp(account) || store.isRunning(account) {
            return store.launchStatus
        }
        return "Starts @\(account.username) with the game and server above"
    }

    private var numericPlaceID: Int64? {
        guard let value = Int64(placeID.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    private var gamePlaceID: Binding<String> {
        placeIDBindingResettingServer(
            placeID: $placeID,
            serverSelection: $serverSelection
        )
    }

    private func setDraftMembership(_ group: String, isMember: Bool) {
        if isMember {
            draft.groups = ManagedAccount.normalizedGroups(draft.groups + [group])
        } else {
            draft.groups.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame }
        }
    }

    private func openWebsite(_ destination: AccountWebsiteDestination) {
        Task {
            guard await store.prepareWebsiteSession(accountID: account.id) else { return }
            openWindow(value: AccountWebsiteRequest(accountID: account.id, destination: destination))
        }
    }
}

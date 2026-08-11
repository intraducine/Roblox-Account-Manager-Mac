import RAMacCore
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    let showsLaunchBar: Bool
    let onRequestModifiedFallback: () -> Void
    @State private var draft: ManagedAccount
    @State private var placeID: String
    @State private var serverSelection: RobloxServerSelection
    @State private var showsNewGroup = false
    @State private var newGroupName = ""

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
        VStack(spacing: 0) {
            Form {
                Section {
                    identityHeader
                        .padding(.vertical, 6)
                }

                Section("Account Details") {
                    LabeledContent("Alias") {
                        TextField("Alias", text: $draft.alias, prompt: Text("Name shown in the sidebar"))
                            .labelsHidden()
                            .frame(maxWidth: 360)
                    }
                }

                Section("Account Status") {
                    AccountHealthRow(store: store, account: account)
                }

                Section("Roblox Website") {
                    HStack {
                        Button("Home") { openWebsite(.home) }
                        Button("My Profile") { openWebsite(.profile) }
                        Button("Settings") { openWebsite(.settings) }
                        Button("Security") { openWebsite(.security) }
                    }
                }

                Section("Groups") {
                    if store.groupNames.isEmpty {
                        Text("This account is not in a group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.groupNames, id: \.self) { group in
                            Toggle(
                                group,
                                isOn: Binding(
                                    get: { draft.belongs(to: group) },
                                    set: { isMember in setDraftMembership(group, isMember: isMember) }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                    Button("New Group…", systemImage: "plus") {
                        newGroupName = ""
                        showsNewGroup = true
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(minHeight: 110)
                }

                Section {
                    HStack {
                        Text("Saves alias, group memberships, and notes.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save Changes") { store.update(draft) }
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            .formStyle(.grouped)

            if showsLaunchBar {
                accountLaunchBar
            }
        }
        .sheet(isPresented: $showsNewGroup) {
            NewGroupSheet(
                name: $newGroupName,
                message: "Create a group and add this account to it. Save the account to keep the new membership.",
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
        .onChange(of: account.groups) { groups in
            draft.groups = groups
        }
        .onChange(of: account.savedServer) { savedServer in
            serverSelection = .savedValue(savedServer)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text("@\(draft.username) · User \(draft.userID)")
                    .foregroundStyle(.secondary)
                if store.isRunning(account) {
                    Label("Running in a separate Roblox instance", systemImage: "play.fill")
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

    private var accountLaunchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Launch Account", systemImage: "play.fill")
                    .fontWeight(.semibold)
                Text("@\(draft.username)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.launchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LaunchClientNotice(
                store: store,
                onRequestModifiedFallback: onRequestModifiedFallback
            )

            HStack(spacing: 10) {
                TextField("Place ID", text: gamePlaceID)
                    .frame(width: 170)
                    .disabled(store.isRunning(account))
                ExperienceChooserButton(store: store, placeID: gamePlaceID)
                    .disabled(store.isRunning(account))
                ServerSelectionControl(
                    store: store,
                    placeID: $placeID,
                    selection: $serverSelection,
                    requiredSpaces: 1
                )
                    .disabled(store.isRunning(account))

                if store.isRunning(account) {
                    Button(store.isWorking ? "Stopping" : "Stop") {
                        Task { await store.stop(account) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(store.isWorking)
                } else {
                    Button(store.isWorking ? "Launching" : "Launch") {
                        Task { await store.launch(account: draft, placeText: placeID, server: serverSelection) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)
                }
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(.bar)
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

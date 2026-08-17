import RAMacCore
import SwiftUI

struct LaunchSetsView: View {
    @ObservedObject var store: AccountStore
    @State private var selectedID: UUID?
    @State private var draft: LaunchSet?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(store.launchSets, selection: $selectedID) { launchSet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(launchSet.name).fontWeight(.medium)
                        Text("\(launchSet.experienceName ?? (launchSet.placeID > 0 ? "Saved game" : "No game chosen")) · \(launchSet.serverStrategy.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(resolvedAccountLabel(for: launchSet)) · \(arrangementTitle(for: launchSet.windowArrangement))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(launchSet.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        run(launchSet)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { selectedIDs in
                    if let launchSet = launchSet(in: selectedIDs) {
                        Button {
                            run(launchSet)
                        } label: {
                            Label("Run Launch Set", systemImage: "play.fill")
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            remove(launchSet)
                        }
                    }
                }
                Divider()
                Button("New Launch Set", systemImage: "plus") { createDraft() }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppGeometry.windowEdgeControlInset)
                    .padding(.vertical, AppGeometry.windowEdgeControlInset)
            }
            .navigationTitle("Launch Sets")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let draft {
                LaunchSetEditor(store: store, draft: binding(for: draft)) {
                    store.saveLaunchSet(self.draft ?? draft)
                    selectedID = draft.id
                }
                .id(draft.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("A Launch Set is a saved shortcut for accounts, a game, and a server choice. Choose one or create a new one.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: selectedID) { id in
            guard let id else {
                draft = nil
                return
            }
            if draft?.id != id {
                draft = store.launchSets.first(where: { $0.id == id })
            }
        }
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private func createDraft() {
        let launchSet = LaunchSet(name: "New Launch Set", placeID: 0)
        draft = launchSet
        selectedID = launchSet.id
    }

    private func run(_ launchSet: LaunchSet) {
        guard store.runningLaunchSetID == nil,
              !store.isWorking,
              !store.isBatchLaunching,
              !store.isOpeningSelectedApps else { return }
        selectedID = launchSet.id
        Task { await store.runLaunchSet(launchSet) }
    }

    private func launchSet(in selectedIDs: Set<UUID>) -> LaunchSet? {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
        return store.launchSets.first(where: { $0.id == id })
    }

    private func remove(_ launchSet: LaunchSet) {
        store.removeLaunchSet(launchSet)
        if selectedID == launchSet.id {
            selectedID = nil
            draft = nil
        }
    }

    private func resolvedAccountLabel(for launchSet: LaunchSet) -> String {
        let count = store.accounts.filter { account in
            launchSet.accountIDs.contains(account.id)
                || launchSet.groupNames.contains { account.belongs(to: $0) }
        }.count
        return "\(count) account\(count == 1 ? "" : "s")"
    }

    private func arrangementTitle(for policy: WindowArrangementPolicy) -> String {
        switch policy {
        case .savedPlacements: return "Saved placements"
        case .custom: return "Custom window layout"
        case .unchanged: return "Windows unchanged"
        }
    }

    private func binding(for fallback: LaunchSet) -> Binding<LaunchSet> {
        Binding(get: { draft ?? fallback }, set: { draft = $0 })
    }
}

private struct LaunchSetEditor: View {
    @ObservedObject var store: AccountStore
    @Binding var draft: LaunchSet
    let onSave: () -> Void
    @State private var placeText: String
    @State private var strategyKind: String
    @State private var privateLink: String

    init(store: AccountStore, draft: Binding<LaunchSet>, onSave: @escaping () -> Void) {
        self.store = store
        _draft = draft
        self.onSave = onSave
        _placeText = State(initialValue: draft.wrappedValue.placeID > 0 ? String(draft.wrappedValue.placeID) : "")
        if case .privateServerLink(let link) = draft.wrappedValue.serverStrategy {
            _strategyKind = State(initialValue: "private")
            _privateLink = State(initialValue: link)
        } else {
            _strategyKind = State(initialValue: Self.kind(for: draft.wrappedValue.serverStrategy))
            _privateLink = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section {
                Text("Save the accounts, game, and server choice that you often use together. Running a Launch Set starts every available account in it.")
                    .foregroundStyle(.secondary)
            }
            Section("Launch Set") {
                TextField("Name", text: $draft.name)
            }
            Section("Launch") {
                LabeledContent("Game") {
                    ExperienceChooserButton(
                        store: store,
                        placeID: gamePlaceID,
                        knownName: draft.experienceName
                    ) { experience in
                        draft.experienceName = experience.experienceName
                    }
                }
                Picker("Server choice", selection: $strategyKind) {
                    Text("Let Roblox choose").tag("automatic")
                    Text("Browse public servers when run").tag("browse")
                    Text("Choose a player when run").tag("player")
                    Text("Use a private server link").tag("private")
                }
                if strategyKind == "private" {
                    SecureField("Private server link", text: $privateLink)
                    if !store.privateServers.isEmpty {
                        Menu("Choose Saved Private Server") {
                            ForEach(store.privateServers) { server in
                                Button(server.name) {
                                    privateLink = server.link
                                    gamePlaceID.wrappedValue = String(server.placeID)
                                }
                            }
                        }
                    }
                    Text("Private links stay on this Mac and are excluded from normal backups.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                FullWidthDisclosure("Advanced options") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Place ID") {
                            TextField("Place ID", text: gamePlaceID)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                        }
                        Text("Choose Game fills this number automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Windows") {
                InlineWindowArrangementEditor(
                    controller: store.windowLayout,
                    accounts: resolvedAccounts,
                    assignments: effectiveWindowAssignments,
                    usesSavedPlacements: draft.windowArrangement.usesSavedPlacements,
                    customStatus: "Using the custom layout saved with this Launch Set.",
                    disabled: false,
                    onAssignmentsChange: { assignments in
                        draft.windowArrangement = .custom(assignments)
                    },
                    onUseSavedPlacements: {
                        draft.windowArrangement = .savedPlacements
                    }
                )
            }
            Section("Accounts") {
                ForEach(store.accounts) { account in
                    Toggle(account.title, isOn: membership(account.id, in: $draft.accountIDs))
                        .toggleStyle(.checkbox)
                }
            }
            Section("Groups") {
                ForEach(store.groupNames, id: \.self) { group in
                    Toggle(group, isOn: groupMembership(group))
                        .toggleStyle(.checkbox)
                }
            }
            Section {
                HStack {
                    Button("Run Launch Set") {
                        applyFields()
                        Task { await store.runLaunchSet(draft) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid
                        || store.runningLaunchSetID != nil
                        || store.isWorking
                        || store.isBatchLaunching
                        || store.isOpeningSelectedApps)
                    Spacer()
                    Button("Save Changes") { applyFields(); onSave() }
                        .disabled(!isValid)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
    }

    private var resolvedAccounts: [ManagedAccount] {
        store.accounts.filter { account in
            draft.accountIDs.contains(account.id)
                || draft.groupNames.contains { account.belongs(to: $0) }
        }
    }

    private var effectiveWindowAssignments: [WindowLayoutAssignment] {
        let accountIDs = Set(resolvedAccounts.map(\.id))
        return draft.windowArrangement.effectiveAssignments(
            savedAssignments: store.windowLayout.savedAssignments(for: accountIDs),
            accountIDs: accountIDs
        )
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int64(placeText) ?? 0) > 0
            && (strategyKind != "private"
                || RobloxLaunchURLBuilder.privateLinkCode(from: privateLink) != nil
                || RobloxLaunchURLBuilder.privateShareCode(from: privateLink) != nil)
    }

    private var gamePlaceID: Binding<String> {
        Binding(
            get: { placeText },
            set: { newValue in
                placeText = newValue
                draft.experienceName = nil
            }
        )
    }

    private func applyFields() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.placeID = Int64(placeText) ?? 0
        switch strategyKind {
        case "browse": draft.serverStrategy = .browseBeforeLaunch
        case "player": draft.serverStrategy = .joinPlayer
        case "private": draft.serverStrategy = .privateServerLink(privateLink)
        default: draft.serverStrategy = .robloxChooses
        }
        if case .custom(let assignments) = draft.windowArrangement {
            let validIDs = Set(resolvedAccounts.map(\.id))
            draft.windowArrangement = .custom(assignments.filter { validIDs.contains($0.accountID) })
        }
    }

    private func membership(_ id: UUID, in ids: Binding<[UUID]>) -> Binding<Bool> {
        Binding(
            get: { ids.wrappedValue.contains(id) },
            set: { selected in
                if selected { if !ids.wrappedValue.contains(id) { ids.wrappedValue.append(id) } }
                else { ids.wrappedValue.removeAll { $0 == id } }
            }
        )
    }

    private func groupMembership(_ group: String) -> Binding<Bool> {
        Binding(
            get: { draft.groupNames.contains { $0.caseInsensitiveCompare(group) == .orderedSame } },
            set: { selected in
                draft.setGroupSelection(group, selected: selected, accounts: store.accounts)
            }
        )
    }

    private static func kind(for strategy: ServerStrategy) -> String {
        switch strategy {
        case .robloxChooses: return "automatic"
        case .browseBeforeLaunch: return "browse"
        case .joinPlayer: return "player"
        case .privateServerLink: return "private"
        }
    }
}

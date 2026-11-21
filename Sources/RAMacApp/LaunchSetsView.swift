import RAMacCore
import SwiftUI

struct LaunchSetsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @State private var selectedID: UUID?
    @State private var draft: LaunchSet?
    @State private var reviewedSet: (setID: UUID, requestID: UUID)?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(store.launchSets, selection: $selectedID) { launchSet in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(launchSet.name).fontWeight(.medium)
                            if launchSet.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Pinned")
                            }
                        }
                        Text(gameSummary(for: launchSet))
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

                        Button(launchSet.isPinned ? "Unpin from Accounts" : "Pin in Accounts") {
                            store.setLaunchSetPinned(launchSet.id, pinned: !launchSet.isPinned)
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
                LaunchSetEditor(
                    store: store,
                    draft: binding(for: draft),
                    reviewID: reviewedSet?.setID == draft.id ? reviewedSet?.requestID : nil,
                    onRun: run,
                    onSave: {
                        if store.saveLaunchSet(self.draft ?? draft) { selectedID = draft.id }
                    }
                )
                .id(draft.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Save which accounts to open and where they should join.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .robloxUpdateRecovery(store)
        .onChange(of: selectedID) { id in
            guard let id else {
                draft = nil
                return
            }
            if draft?.id != id {
                draft = store.launchSets.first(where: { $0.id == id })
            }
        }
        .onChange(of: store.launchSets) { sets in
            if let saved = sets.first(where: { $0.id == draft?.id }) {
                draft?.isPinned = saved.isPinned
            }
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
        let requestID = UUID()
        reviewedSet = (launchSet.id, requestID)
        Task {
            let nextStep = await store.runLaunchSet(launchSet, requestID: requestID)
            switch nextStep {
            case .browsePublicServers: openWindow(id: "accounts")
            case .choosePlayer: openWindow(id: "joinable-players")
            case nil: break
            }
        }
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
        let count = resolvedAccounts(for: launchSet).count
        return "\(count) account\(count == 1 ? "" : "s")"
    }

    private func resolvedAccounts(for launchSet: LaunchSet) -> [ManagedAccount] {
        store.accounts.filter { account in
            launchSet.accountIDs.contains(account.id)
                || launchSet.groupNames.contains { account.belongs(to: $0) }
        }
    }

    private func gameSummary(for launchSet: LaunchSet) -> String {
        let accounts = resolvedAccounts(for: launchSet)
        let overrides = accounts.compactMap { launchSet.accountGames[$0.id] }.filter { $0.placeID > 0 }
        let usesSharedGame = overrides.count < accounts.count && launchSet.placeID > 0
        var places = Set(overrides.map(\.placeID))
        if usesSharedGame { places.insert(launchSet.placeID) }
        if places.count > 1 { return "\(places.count) games" }
        if usesSharedGame || (accounts.isEmpty && launchSet.placeID > 0) {
            return "\(launchSet.experienceName ?? "Saved game") · \(launchSet.serverStrategy.title)"
        }
        return overrides.first.map { $0.name ?? "Saved game" } ?? "No game chosen"
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
    let reviewID: UUID?
    let onRun: (LaunchSet) -> Void
    let onSave: () -> Void
    @State private var placeText: String
    @State private var strategyKind: String
    @State private var privateLink: String

    init(
        store: AccountStore, draft: Binding<LaunchSet>, reviewID: UUID?,
        onRun: @escaping (LaunchSet) -> Void, onSave: @escaping () -> Void
    ) {
        self.store = store
        _draft = draft
        self.reviewID = reviewID
        self.onRun = onRun
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
                Text("Choose one game for everyone or set a game for each account in Per-Account Options.")
                    .foregroundStyle(.secondary)
            }
            Section("Launch Set") {
                TextField("Name", text: $draft.name)
            }
            Section("Launch") {
                LabeledContent("Shared Game") {
                    ExperienceChooserButton(
                        store: store,
                        placeID: gamePlaceID,
                        knownName: draft.experienceName
                    ) { experience in
                        draft.experienceName = experience.experienceName
                    }
                }
                if sharedPlaceID > 0 {
                    Button("Clear Shared Game") { gamePlaceID.wrappedValue = "" }
                }
                if usesSharedGame {
                    Picker("Shared Server", selection: $strategyKind) {
                        Text("Let Roblox choose").tag("automatic")
                        Text("Browse public servers when run").tag("browse")
                        Text("Choose a player when run").tag("player")
                        Text("Use a private server link").tag("private")
                    }
                }
                if usesSharedGame && strategyKind == "private" {
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
            Section("Graphics and sound") {
                LaunchSettingsOverrideEditor(
                    defaults: store.launchSettings,
                    overrideSettings: $draft.launchSettings,
                    customDescription: "Using settings saved with this Launch Set."
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
            if !resolvedAccounts.isEmpty {
                Section {
                    FullWidthDisclosure("Per-Account Options") {
                        AccountLaunchOptions(
                            store: store, accounts: resolvedAccounts, hasSharedGame: sharedPlaceID > 0,
                            defaults: draft.launchSettings ?? store.launchSettings,
                            games: $draft.accountGames, settings: $draft.accountSettings
                        )
                    }
                    if usesSharedGame && strategyKind == "player" && hasAccountGames {
                        Text("Choose a player requires a shared game for all accounts.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                FullWidthDisclosure("Window Layout") {
                    InlineWindowArrangementEditor(
                        controller: store.windowLayout,
                        accounts: resolvedAccounts,
                        assignments: effectiveWindowAssignments,
                        usesSavedPlacements: draft.windowArrangement.usesSavedPlacements,
                        customStatus: "Using the custom window arrangement saved with this Launch Set.",
                        disabled: false,
                        onAssignmentsChange: { draft.windowArrangement = .custom($0) },
                        onUseSavedPlacements: { draft.windowArrangement = .savedPlacements }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
        .onChange(of: draft) { _ in dismissPreviousReview() }
        .onChange(of: placeText) { _ in dismissPreviousReview() }
        .onChange(of: strategyKind) { _ in dismissPreviousReview() }
        .onChange(of: privateLink) { _ in dismissPreviousReview() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let reviewID {
                    BatchReadinessView(store: store, expectedID: reviewID)
                }
                HStack(spacing: 12) {
                    Spacer()
                    Button("Save Changes") { applyFields(); onSave() }
                        .disabled(!isValid)
                    Button("Run Launch Set") { applyFields(); onRun(draft) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid || store.runningLaunchSetID != nil || store.isBusyWithRoblox)
                }
            }
            .padding(14)
            .background(.bar)
        }
    }

    private func dismissPreviousReview() {
        if let reviewID { store.dismissBatchReview(expectedID: reviewID) }
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
            && !resolvedAccounts.isEmpty
            && (sharedPlaceID > 0 || allAccountsHaveGames)
            && (!usesSharedGame || strategyKind != "player" || !hasAccountGames)
            && (!usesSharedGame || strategyKind != "private"
                || RobloxLaunchURLBuilder.privateLinkCode(from: privateLink) != nil
                || RobloxLaunchURLBuilder.privateShareCode(from: privateLink) != nil)
    }

    private var sharedPlaceID: Int64 { max(0, Int64(placeText) ?? 0) }

    private var allAccountsHaveGames: Bool {
        LaunchSetGame.covers(Set(resolvedAccounts.map(\.id)), games: draft.accountGames)
    }

    private var usesSharedGame: Bool { sharedPlaceID > 0 && !allAccountsHaveGames }

    private var hasAccountGames: Bool {
        resolvedAccounts.contains { (draft.accountGames[$0.id]?.placeID ?? 0) > 0 }
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
        draft.placeID = sharedPlaceID
        let selectedIDs = Set(resolvedAccounts.map(\.id))
        draft.accountGames = draft.accountGames.filter { selectedIDs.contains($0.key) && $0.value.placeID > 0 }
        draft.accountSettings = draft.accountSettings.filter { selectedIDs.contains($0.key) }
        switch usesSharedGame ? strategyKind : "automatic" {
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

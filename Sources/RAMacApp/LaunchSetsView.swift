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
                        Text("Place \(launchSet.placeID) · \(launchSet.serverStrategy.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(launchSet.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.removeLaunchSet(launchSet)
                            if selectedID == launchSet.id {
                                selectedID = nil
                                draft = nil
                            }
                        }
                    }
                }
                Divider()
                Button("New Launch Set", systemImage: "plus") { createDraft() }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
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
                    Text("Choose a Launch Set or create one.").foregroundStyle(.secondary)
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
            Section("Launch Set") {
                TextField("Name", text: $draft.name)
                TextField("Experience name (optional)", text: Binding(
                    get: { draft.experienceName ?? "" },
                    set: { draft.experienceName = $0.isEmpty ? nil : $0 }
                ))
                TextField("Place ID", text: $placeText)
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
            Section("Server") {
                Picker("Strategy", selection: $strategyKind) {
                    Text("Roblox chooses").tag("automatic")
                    Text("Browse before launch").tag("browse")
                    Text("Join a player").tag("player")
                    Text("Private server link").tag("private")
                }
                if strategyKind == "private" {
                    SecureField("Private server link", text: $privateLink)
                    if !store.privateServers.isEmpty {
                        Menu("Choose Saved Private Server") {
                            ForEach(store.privateServers) { server in
                                Button(server.name) {
                                    privateLink = server.link
                                    placeText = String(server.placeID)
                                }
                            }
                        }
                    }
                    Text("Private links stay on this Mac and are excluded from normal backups.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Button("Run Launch Set") {
                        applyFields()
                        Task { await store.runLaunchSet(draft) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    Spacer()
                    Button("Save Changes") { applyFields(); onSave() }
                        .disabled(!isValid)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Int64(placeText) ?? 0) > 0
            && (strategyKind != "private" || RobloxLaunchURLBuilder.privateLinkCode(from: privateLink) != nil)
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
                if selected { draft.groupNames = ManagedAccount.normalizedGroups(draft.groupNames + [group]) }
                else { draft.groupNames.removeAll { $0.caseInsensitiveCompare(group) == .orderedSame } }
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

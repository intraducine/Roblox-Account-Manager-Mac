import RAMacCore
import SwiftUI

struct GameLibraryView: View {
    private enum Entry: Hashable {
        case game(Int64)
        case privateServer(UUID)
    }

    @ObservedObject var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: Entry?
    @State private var reviewID: UUID?
    @State private var search = ""
    @State private var selectedAccounts = Set<UUID>()
    @State private var showsGameChooser = false
    @State private var showsPrivateServers = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                gameSection("Favorites", games: games.filter(\.isFavorite))
                gameSection("Recent Games", games: games.filter { !$0.isFavorite })
                if !servers.isEmpty {
                    Section("Private Servers") {
                        ForEach(servers) { server in
                            Label(server.name, systemImage: "lock")
                                .tag(Entry.privateServer(server.id))
                        }
                    }
                }
                if games.isEmpty && servers.isEmpty {
                    Text(search.isEmpty ? "Add a game to start your library." : "No games or servers match.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Search games and servers")
            .navigationTitle("Game Library")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let destination {
                Form {
                    Section("Accounts") {
                        if store.accounts.isEmpty {
                            Button("Add Account") { openWindow(id: "add-account") }
                        }
                        if !store.groupNames.isEmpty {
                            Menu("Select Group") {
                                ForEach(store.groupNames, id: \.self) { group in
                                    Button(group) {
                                        selectedAccounts = Set(store.accounts.filter {
                                            $0.belongs(to: group) && !store.isRunning($0)
                                        }.map(\.id))
                                    }
                                }
                            }
                        }
                        ForEach(store.accounts) { account in
                            Toggle("@\(account.username)", isOn: Binding(
                                get: { selectedAccounts.contains(account.id) && !store.isRunning(account) },
                                set: { if $0 { selectedAccounts.insert(account.id) } else { selectedAccounts.remove(account.id) } }
                            ))
                            .toggleStyle(.checkbox)
                            .disabled(store.isRunning(account))
                            .help(store.isRunning(account) ? "Roblox is already open for this account." : "")
                        }
                    }
                    Section {
                        HStack {
                            Button("Running Accounts") { openWindow(id: "running-accounts") }
                            Spacer()
                            Button(store.isBatchLaunching ? "Starting…" : "Launch") {
                                let requestID = UUID()
                                reviewID = requestID
                                let accountIDs = eligibleIDs
                                Task {
                                    await store.launchFromLibrary(
                                        accountIDs: accountIDs, placeID: destination.placeID,
                                        server: destination.server, requestID: requestID
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(eligibleIDs.isEmpty || store.isBusyWithRoblox)
                        }
                        if let reviewID {
                            BatchReadinessView(store: store, expectedID: reviewID)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(destination.name)
            } else {
                Text("Choose a game or private server.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            Button("Add Game", systemImage: "plus") { showsGameChooser = true }
                .labelStyle(.titleAndIcon)
            Button("Manage Private Servers", systemImage: "lock") { showsPrivateServers = true }
                .labelStyle(.titleAndIcon)
        }
        .sheet(isPresented: $showsGameChooser) {
            ExperienceChooserView(store: store) { game in
                store.addGameToLibrary(game)
                selection = .game(game.placeID)
                showsGameChooser = false
            }
        }
        .sheet(isPresented: $showsPrivateServers) {
            NavigationStack {
                PrivateServerLibraryView(store: store) { server in
                    selection = .privateServer(server.id)
                    showsPrivateServers = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showsPrivateServers = false }.keyboardShortcut(.cancelAction)
                    }
                }
            }
            .frame(width: 680, height: 560)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: selection) { _ in
            clearReview()
        }
        .onChange(of: selectedAccounts) { _ in
            clearReview()
        }
        .robloxUpdateRecovery(store)
    }

    private func clearReview() {
        if let reviewID { store.dismissBatchReview(expectedID: reviewID) }
        reviewID = nil
    }

    @ViewBuilder
    private func gameSection(_ title: String, games: [ExperienceRecord]) -> some View {
        if !games.isEmpty {
            Section(title) {
                ForEach(games) { game in
                    Label {
                        Text(game.experienceName ?? "Place \(game.placeID)")
                    } icon: {
                        if game.thumbnailURLString != nil {
                            ExperienceIcon(experience: game, size: 24)
                        } else {
                            Image(systemName: "gamecontroller")
                        }
                    }
                    .tag(Entry.game(game.placeID))
                    .contextMenu {
                        Button(game.isFavorite ? "Remove Favorite" : "Add Favorite") {
                            store.setExperienceFavorite(game, isFavorite: !game.isFavorite)
                        }
                    }
                }
            }
        }
    }

    private var games: [ExperienceRecord] {
        store.experiences.filter {
            matches($0.experienceName ?? "") || matches(String($0.placeID))
        }.sorted { $0.lastLaunchedAt > $1.lastLaunchedAt }
    }

    private var servers: [SavedPrivateServer] {
        store.privateServers.filter { matches($0.name) || matches(String($0.placeID)) }
    }

    private func matches(_ name: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || name.localizedCaseInsensitiveContains(term)
    }

    private var eligibleIDs: Set<UUID> {
        selectedAccounts.subtracting(store.runningAccountIDs)
    }

    private var destination: (name: String, placeID: Int64, server: RobloxServerSelection)? {
        switch selection {
        case .game(let placeID):
            guard let game = store.experiences.first(where: { $0.placeID == placeID }) else { return nil }
            return (game.experienceName ?? "Place \(placeID)", placeID, .automatic)
        case .privateServer(let id):
            guard let server = store.privateServers.first(where: { $0.id == id }) else { return nil }
            return (server.name, server.placeID, .privateLink(server.link))
        case nil:
            return nil
        }
    }
}

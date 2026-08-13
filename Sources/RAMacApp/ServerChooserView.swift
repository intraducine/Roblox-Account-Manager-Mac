import RAMacCore
import SwiftUI

struct ServerSelectionControl: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var selection: RobloxServerSelection
    let requiredSpaces: Int
    @State private var showsChooser = false

    var body: some View {
        Button(selection.controlTitle) {
            showsChooser = true
        }
        .frame(minWidth: 210)
        .help("Choose where the selected account or accounts will join")
        .accessibilityLabel("Choose server. \(selection.accessibilitySummary)")
        .sheet(isPresented: $showsChooser) {
            ServerChooserView(
                store: store,
                placeID: $placeID,
                selection: $selection,
                requiredSpaces: max(1, requiredSpaces)
            )
        }
    }
}

private struct ServerChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var selection: RobloxServerSelection
    let requiredSpaces: Int
    @State private var checkingActiveAccountID: UUID?

    private var numericPlaceID: Int64? {
        guard let value = Int64(placeID.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(.automatic)
                    } label: {
                        ChoiceRow(
                            title: "Let Roblox choose",
                            detail: "Join any available public server.",
                            isSelected: selection == .automatic
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        if let numericPlaceID {
                            PublicServerListView(
                                store: store,
                                placeID: numericPlaceID,
                                requiredSpaces: requiredSpaces,
                                onChoose: { choose($0) }
                            )
                        } else {
                            MissingPlaceView()
                        }
                    } label: {
                        ChoiceRow(
                            title: "Browse public servers",
                            detail: numericPlaceID == nil
                                ? "Enter a Place ID before browsing."
                                : "Choose by player count and open spaces."
                        )
                    }

                    NavigationLink {
                        PlayerServerSearchView(store: store) { server, foundPlaceID in
                            placeID = String(foundPlaceID)
                            choose(server)
                        }
                    } label: {
                        ChoiceRow(
                            title: "Join a player",
                            detail: "Find a server that Roblox makes public for that player."
                        )
                    }

                    NavigationLink {
                        PrivateServerLibraryView(store: store) { server in
                            store.markPrivateServerUsed(server)
                            placeID = String(server.placeID)
                            choose(.privateLink(server.link))
                        }
                    } label: {
                        ChoiceRow(
                            title: "Private servers",
                            detail: "Choose a saved link or add another."
                        )
                    }
                }

                if !runningPublicTargets.isEmpty {
                    Section("Servers used by running accounts") {
                        ForEach(runningPublicTargets) { record in
                            Button {
                                Task { await chooseRunningTarget(record) }
                            } label: {
                                ChoiceRow(
                                    title: runningTargetTitle(record),
                                    detail: checkingActiveAccountID == record.accountID
                                        ? "Checking that the server is still public."
                                        : "Reuse this verified server after a fresh capacity check."
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(checkingActiveAccountID != nil)
                        }
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        ManualJobEntryView(placeIDIsValid: numericPlaceID != nil) { choose($0) }
                    } label: {
                        ChoiceRow(
                            title: "Enter a Job ID",
                            detail: "Advanced: use the temporary code for one running server."
                        )
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Choose a Server")
        }
        .frame(width: 680, height: 560)
        .alert(item: $store.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func choose(_ newSelection: RobloxServerSelection) {
        selection = newSelection
        dismiss()
    }

    private var runningPublicTargets: [ActiveLaunchTargetRecord] {
        guard let numericPlaceID else { return [] }
        return store.activeLaunchTargets.values.filter {
            $0.placeID == numericPlaceID
                && $0.targetKind == .verifiedPublicJob
                && $0.jobID != nil
        }.sorted { $0.launchedAt > $1.launchedAt }
    }

    private func runningTargetTitle(_ record: ActiveLaunchTargetRecord) -> String {
        let accountName = store.accounts.first(where: { $0.id == record.accountID })?.title ?? "Running account"
        return "Use \(accountName)'s server"
    }

    @MainActor
    private func chooseRunningTarget(_ record: ActiveLaunchTargetRecord) async {
        guard let jobID = record.jobID else { return }
        checkingActiveAccountID = record.accountID
        defer { checkingActiveAccountID = nil }
        switch await store.verifyPublicServer(placeID: record.placeID, jobID: jobID) {
        case .verifiedPublic(let server):
            choose(.publicInstance(jobID: server.id, playing: server.playing, maxPlayers: server.maxPlayers))
        default:
            store.notice = .init(
                title: "The running server is no longer available",
                message: "Refresh public servers or let Roblox choose another server."
            )
        }
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct MissingPlaceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Enter a Place ID First")
                .font(.title2.weight(.semibold))
            Text("Close this window, enter the number from the Roblox game link, and open Choose Server again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .navigationTitle("Place ID Required")
    }
}

private struct PublicServerListView: View {
    @ObservedObject var store: AccountStore
    let placeID: Int64
    let requiredSpaces: Int
    let onChoose: (RobloxServerSelection) -> Void
    @State private var servers: [RobloxPublicServer] = []
    @State private var nextCursor: String?
    @State private var fetchedAt: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var orderedServers: [RobloxPublicServer] {
        servers.sorted { left, right in
            let leftFits = left.openSpaces >= requiredSpaces
            let rightFits = right.openSpaces >= requiredSpaces
            if leftFits != rightFits { return leftFits && !rightFits }
            if left.playing != right.playing { return left.playing > right.playing }
            return left.id < right.id
        }
    }

    var body: some View {
        Group {
            if isLoading && servers.isEmpty {
                ProgressView("Loading public servers")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, servers.isEmpty {
                ServerMessageView(
                    title: "Servers Could Not Load",
                    message: errorMessage,
                    actionTitle: "Try Again",
                    action: { Task { await load(cursor: nil, replacing: true, forceRefresh: true) } }
                )
            } else if servers.isEmpty {
                ServerMessageView(
                    title: "No Public Servers Found",
                    message: "Roblox did not return an available public server for this place."
                )
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(requiredSpaces == 1
                                ? "Choose a server with at least one open space."
                                : "Choose a server with at least \(requiredSpaces) open spaces for the selected accounts.")
                                .foregroundStyle(.secondary)
                            Button(isLoading ? "Refreshing Server List" : "Refresh Server List") {
                                Task { await load(cursor: nil, replacing: true, forceRefresh: true) }
                            }
                            .disabled(isLoading)
                            .help("Roblox limits how often server lists can refresh")
                        }
                        .padding(.vertical, 2)
                    }

                    Section("Available servers") {
                        ForEach(orderedServers) { server in
                            Button {
                                onChoose(.publicInstance(
                                    jobID: server.id,
                                    playing: server.playing,
                                    maxPlayers: server.maxPlayers
                                ))
                            } label: {
                                PublicServerRow(server: server, requiredSpaces: requiredSpaces)
                            }
                            .buttonStyle(.plain)
                            .disabled(server.openSpaces < requiredSpaces)
                        }
                    }

                    if let nextCursor {
                        Section {
                            Button(isLoading ? "Loading More Servers" : "Load More Servers") {
                                Task { await load(cursor: nextCursor, replacing: false) }
                            }
                            .disabled(isLoading)
                        }
                    }
                }
            }
        }
        .navigationTitle("Public Servers")
        .safeAreaInset(edge: .bottom) {
            if let fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened)). Results are cached for one minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
        .task {
            if servers.isEmpty { await load(cursor: nil, replacing: true) }
        }
    }

    private func load(cursor: String?, replacing: Bool, forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await store.publicServerPage(
                placeID: placeID,
                cursor: cursor,
                forceRefresh: forceRefresh
            )
            if replacing {
                servers = snapshot.page.data
            } else {
                let known = Set(servers.map(\.id))
                servers.append(contentsOf: snapshot.page.data.filter { !known.contains($0.id) })
            }
            nextCursor = snapshot.page.nextPageCursor
            fetchedAt = snapshot.fetchedAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PublicServerRow: View {
    let server: RobloxPublicServer
    let requiredSpaces: Int

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(server.playing) of \(server.maxPlayers) players")
                    .fontWeight(.medium)
                Text(spaceDescription)
                    .font(.callout)
                    .foregroundStyle(server.openSpaces >= requiredSpaces ? Color.secondary : Color.red)
            }
            Spacer()
            if let ping = server.ping {
                Text("Roblox ping: \(ping) ms")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var spaceDescription: String {
        if server.openSpaces < requiredSpaces {
            return "Not enough room for \(requiredSpaces) accounts"
        }
        return "\(server.openSpaces) space\(server.openSpaces == 1 ? "" : "s") open"
    }
}

private struct PlayerServerSearchView: View {
    @ObservedObject var store: AccountStore
    let onChoose: (RobloxServerSelection, Int64) -> Void
    @State private var username = ""
    @State private var result: JoinablePlayerServer?
    @State private var message: String?
    @State private var isSearching = false

    var body: some View {
        Form {
            Section {
                Text("This search works only when Roblox makes the player's current game and server public. If the player is friends with one of your saved accounts, use Find Players instead. It can check what that account is allowed to see.")
                    .foregroundStyle(.secondary)
            }

            Section("Player") {
                TextField("Roblox username", text: $username)
                    .onSubmit { Task { await search() } }
                Button(isSearching ? "Searching" : "Find Player") {
                    Task { await search() }
                }
                .disabled(isSearching || cleanUsername.isEmpty)
            }

            if let result,
               let placeID = result.presence.placeId,
               let jobID = result.presence.gameId,
               !jobID.isEmpty {
                Section("Reported server") {
                    LabeledContent("Player", value: "@\(result.user.name)")
                    LabeledContent("Location", value: result.presence.lastLocation ?? "Roblox game")
                    Text("Roblox will check this account's access and server space when it opens.")
                        .foregroundStyle(.secondary)
                    Button("Join @\(result.user.name)'s Server") {
                        onChoose(.manualJob(jobID), placeID)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let message {
                Section("Result") {
                    Text(message)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Join a Player")
    }

    private var cleanUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private func search() async {
        guard !cleanUsername.isEmpty, !isSearching else { return }
        isSearching = true
        result = nil
        message = nil
        defer { isSearching = false }
        do {
            let found = try await store.joinableServer(for: cleanUsername)
            if found.presence.placeId != nil,
               let gameID = found.presence.gameId,
               !gameID.isEmpty {
                result = found
            } else if found.presence.userPresenceType == 0 {
                message = "Roblox did not provide a current experience for @\(found.user.name). The player may be offline or may limit who can see their activity."
            } else {
                message = "Roblox shows that this player is in an experience, but it did not provide a server that this app can target."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PrivateServerLibraryView: View {
    @ObservedObject var store: AccountStore
    let onChoose: (SavedPrivateServer) -> Void
    @State private var name = ""
    @State private var link = ""
    @State private var pendingRemoval: SavedPrivateServer?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Text("Choose a saved server or add a link. Roblox still checks each account's permission when it joins.")
                    .foregroundStyle(.secondary)
            }
            Section("Saved private servers") {
                if store.privateServers.isEmpty {
                    Text("No private servers are saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.privateServers) { server in
                        HStack(spacing: 12) {
                            Button {
                                onChoose(server)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(server.name)
                                        .fontWeight(.medium)
                                    Text("Place ID \(server.placeID)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                pendingRemoval = server
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(server.name)")
                            .accessibilityLabel("Remove \(server.name)")
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            Section("Add a private server") {
                TextField("Name", text: $name, prompt: Text("For example, Friends server"))
                SecureField("Private server link", text: $link)
                if shareCode != nil {
                    Text("This is a current Roblox share link. The app will check the link with one saved account now. Roblox will check access again for every account you launch.")
                        .foregroundStyle(.secondary)
                } else if !cleanLink.isEmpty,
                          parsedPlaceID == nil {
                    Text("Paste a complete Roblox private server link. You can use a current /share link or an older /games link.")
                        .foregroundStyle(.red)
                } else if let parsedPlaceID {
                    Text("This link is for Place ID \(parsedPlaceID).")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        if let server = await store.savePrivateServer(name: cleanName, link: cleanLink) {
                            onChoose(server)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking Link")
                        } else {
                            Text("Save and Use Private Server")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(cleanName.isEmpty || (parsedPlaceID == nil && shareCode == nil) || isSaving)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Private Servers")
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this private server")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            if let pendingRemoval {
                Button("Remove Private Server", role: .destructive) {
                    store.removePrivateServer(pendingRemoval)
                    self.pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes the saved link from this Mac. It does not change the server on Roblox.")
        }
    }

    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanLink: String {
        link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPlaceID: Int64? {
        RobloxLaunchURLBuilder.privateServerPlaceID(from: cleanLink)
    }

    private var shareCode: String? {
        RobloxLaunchURLBuilder.privateShareCode(from: cleanLink)
    }
}

private struct ManualJobEntryView: View {
    let placeIDIsValid: Bool
    let onChoose: (RobloxServerSelection) -> Void
    @State private var jobID = ""

    var body: some View {
        Form {
            Section {
                Text("A Job ID is the unique code for one public server that is already running. It stops working when that server closes.")
                    .foregroundStyle(.secondary)
            }
            Section("Job ID") {
                TextField("00000000-0000-0000-0000-000000000000", text: $jobID)
                if !cleanJobID.isEmpty, UUID(uuidString: cleanJobID) == nil {
                    Text("Enter a complete Job ID.")
                        .foregroundStyle(.red)
                }
                Button("Use Job ID") {
                    onChoose(.manualJob(cleanJobID))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!placeIDIsValid || UUID(uuidString: cleanJobID) == nil)
            }
            if !placeIDIsValid {
                Section("Place ID required") {
                    Text("Close this window and enter a Place ID before using a Job ID.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Enter a Job ID")
    }

    private var cleanJobID: String {
        jobID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ServerMessageView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private extension RobloxServerSelection {
    var controlTitle: String {
        switch self {
        case .automatic:
            return "Server: Roblox chooses"
        case .publicInstance(_, let playing, let maxPlayers):
            return "Server: \(playing) of \(maxPlayers) players"
        case .player(let username, _, _):
            return "Server: Join @\(username)"
        case .privateLink:
            return "Server: Private link"
        case .manualJob:
            return "Server: Entered Job ID"
        }
    }

    var accessibilitySummary: String {
        switch self {
        case .automatic:
            return "Roblox chooses an available public server."
        case .publicInstance(_, let playing, let maxPlayers):
            return "Selected public server with \(playing) of \(maxPlayers) players."
        case .player(let username, _, _):
            return "Join \(username)'s server."
        case .privateLink:
            return "Use a private server link."
        case .manualJob:
            return "Use a manually entered Job ID."
        }
    }
}

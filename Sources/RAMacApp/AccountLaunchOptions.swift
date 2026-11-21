import RAMacCore
import SwiftUI

struct AccountLaunchOptions: View {
    @ObservedObject var store: AccountStore
    let accounts: [ManagedAccount]
    let hasSharedGame: Bool
    let defaults: RobloxLaunchSettings
    @Binding var games: [UUID: LaunchSetGame]
    @Binding var settings: [UUID: RobloxLaunchSettings]
    @State private var selectedID: UUID?

    var body: some View {
        if let id = accounts.first(where: { $0.id == selectedID })?.id ?? accounts.first?.id {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Account", selection: Binding(get: { id }, set: { selectedID = $0 })) {
                    ForEach(accounts) { account in
                        Text("@\(account.username)").tag(account.id)
                    }
                }
                HStack {
                    Text(games[id] == nil && hasSharedGame ? "Uses the shared game" : "Game")
                    Spacer()
                    ExperienceChooserButton(
                        store: store,
                        placeID: Binding(
                            get: { games[id].map { String($0.placeID) } ?? "" },
                            set: { value in
                                if let place = Int64(value), games[id]?.placeID != place {
                                    games[id] = LaunchSetGame(placeID: place)
                                }
                            }
                        ),
                        knownName: games[id]?.name
                    ) { experience in
                        games[id] = LaunchSetGame(placeID: experience.placeID, name: experience.experienceName)
                    }
                }
                HStack {
                    if !store.privateServers.isEmpty {
                        Menu("Choose Private Server") {
                            ForEach(store.privateServers) { server in
                                Button(server.name) {
                                    games[id] = LaunchSetGame(
                                        placeID: server.placeID, name: server.name, privateServerID: server.id
                                    )
                                }
                            }
                        }
                    }
                    if games[id] != nil {
                        Button(hasSharedGame ? "Use Shared Game" : "Remove Game") { games[id] = nil }
                    }
                    if let serverID = games[id]?.privateServerID {
                        Text(store.privateServers.first { $0.id == serverID }?.name ?? "Private server missing")
                            .foregroundStyle(.secondary)
                    }
                }
                LaunchSettingsOverrideEditor(
                    defaults: defaults,
                    overrideSettings: Binding(get: { settings[id] }, set: { settings[id] = $0 }),
                    customDescription: "Using settings for this account.",
                    defaultsDescription: "Using shared graphics and sound.",
                    resetTitle: "Use Shared Settings"
                )
            }
            .id(id)
        }
    }
}

struct BatchReadinessView: View {
    @ObservedObject var store: AccountStore
    var expectedID: UUID?

    var body: some View {
        if let reviewID = store.batchReviewID, expectedID == nil || expectedID == reviewID {
            let ready = store.accounts.filter { store.batchReadyIDs.contains($0.id) }
            VStack(alignment: .leading, spacing: 8) {
                Text(ready.isEmpty ? "No accounts are ready to launch" : "\(ready.count) ready to launch")
                    .fontWeight(.medium)
                if !ready.isEmpty {
                    FullWidthDisclosure("Ready accounts") {
                        Text(ready.map { "@\($0.username)" }.joined(separator: ", "))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !blocked.isEmpty {
                    FullWidthDisclosure("Accounts that need attention") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(blocked) { account in
                                if store.lastBatchResults[account.id]?.healthMessage != nil {
                                    BatchAccountIssueRow(store: store, account: account)
                                } else if let message = store.lastBatchResults[account.id]?.errorMessage {
                                    Text("@\(account.username): \(message)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !ready.isEmpty {
                    Button("Launch Ready Accounts") {
                        Task { await store.launchReadyAccounts(expectedID: reviewID) }
                    }
                        .disabled(store.isBusyWithRoblox || store.robloxUpdateRecovery != nil)
                }
            }
        }
    }

    private var blocked: [ManagedAccount] {
        store.accounts.filter { store.lastBatchResults[$0.id]?.errorMessage != nil }
    }
}

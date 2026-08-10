import RAMacCore
import SwiftUI

struct AccountDetailView: View {
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    let showsLaunchBar: Bool
    @State private var draft: ManagedAccount
    @State private var placeID: String
    @State private var server: String

    init(store: AccountStore, account: ManagedAccount, showsLaunchBar: Bool = true) {
        self.store = store
        self.account = account
        self.showsLaunchBar = showsLaunchBar
        _draft = State(initialValue: account)
        _placeID = State(initialValue: account.savedPlaceID)
        _server = State(initialValue: account.savedServer)
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
                    LabeledContent("Group") {
                        TextField("Group", text: $draft.group, prompt: Text("Default"))
                            .labelsHidden()
                            .frame(maxWidth: 360)
                    }
                    HStack {
                        Spacer()
                        Button("Save Changes") { store.update(draft) }
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(minHeight: 110)
                }
            }
            .formStyle(.grouped)

            if showsLaunchBar {
                accountLaunchBar
            }
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
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
                Text("· \(store.launchMode.shortTitle)")
                    .foregroundStyle(store.launchMode == .modifiedParallel ? Color.orange : .secondary)
                Spacer()
                Text(store.launchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Place ID", text: $placeID)
                    .frame(width: 170)
                    .disabled(store.isRunning(account))
                TextField("Job ID or private server link", text: $server)
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
                        Task { await store.launch(account: draft, placeText: placeID, serverText: server) }
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
}

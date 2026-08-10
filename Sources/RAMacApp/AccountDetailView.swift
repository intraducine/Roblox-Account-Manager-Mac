import RAMacCore
import SwiftUI

struct AccountDetailView: View {
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    @State private var draft: ManagedAccount
    @State private var placeID: String
    @State private var server: String

    init(store: AccountStore, account: ManagedAccount) {
        self.store = store
        self.account = account
        _draft = State(initialValue: account)
        _placeID = State(initialValue: account.savedPlaceID)
        _server = State(initialValue: account.savedServer)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    identityHeader
                    accountEditor
                }
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 28)
                .frame(maxWidth: 900, alignment: .leading)
            }
            launchDock
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .foregroundStyle(RAMPalette.ink)
    }

    private var identityHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RAMPalette.raised
            }
            .frame(width: 88, height: 88)
            .clipShape(AccountCutShape())

            VStack(alignment: .leading, spacing: 5) {
                Text(draft.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("@\(draft.username)  ·  User \(draft.userID)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RAMPalette.muted)
                if store.isRunning(account) {
                    Text("Running in an isolated Roblox instance")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RAMPalette.straw)
                } else if let lastUsed = draft.lastUsed {
                    Text("Last launched \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(RAMPalette.muted)
                } else {
                    Text("Not launched from this Mac yet")
                        .font(.system(size: 12))
                        .foregroundStyle(RAMPalette.muted)
                }
            }
            Spacer()
        }
    }

    private var accountEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Account details")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Save changes") {
                    store.update(draft)
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
            }

            HStack(alignment: .top, spacing: 16) {
                field("Alias", text: $draft.alias, prompt: "Name shown in the shelf")
                field("Group", text: $draft.group, prompt: "Default")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RAMPalette.muted)
                TextEditor(text: $draft.notes)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(9)
                    .frame(minHeight: 92)
                    .background(RAMPalette.shelf)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RAMPalette.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(RAMPalette.shelf)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var launchDock: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Parallel launch dock")
                    .font(.system(size: 16, weight: .bold))
                Text(store.launchStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RAMPalette.muted)
                Spacer()
                Text("as @\(draft.username)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RAMPalette.straw)
                    .padding(.trailing, 22)
            }

            HStack(alignment: .bottom, spacing: 12) {
                launchField("Place ID", text: $placeID, prompt: "920587237")
                    .frame(minWidth: 170, maxWidth: 230)
                    .disabled(store.isRunning(account))
                launchField("Job ID or private server link", text: $server, prompt: "Optional")
                    .disabled(store.isRunning(account))
                if store.isRunning(account) {
                    Button(store.isWorking ? "Stopping" : "Stop instance") {
                        Task { await store.stop(account) }
                    }
                    .buttonStyle(StopButtonStyle())
                    .disabled(store.isWorking)
                } else {
                    Button {
                        Task { await store.launch(account: draft, placeText: placeID, serverText: server) }
                    } label: {
                        HStack(spacing: 7) {
                            Text(store.isWorking ? "Working" : "Launch parallel")
                            Image(systemName: "arrow.up.forward")
                        }
                    }
                    .buttonStyle(LaunchButtonStyle())
                    .disabled(store.isWorking)
                }
            }
        }
        .padding(.leading, 21)
        .padding(.trailing, 28)
        .padding(.vertical, 18)
        .background(RAMPalette.raised)
        .clipShape(LaunchDockShape())
        .accessibilityElement(children: .contain)
    }

    private func launchField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RAMPalette.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RAMPalette.ground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

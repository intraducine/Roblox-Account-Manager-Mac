import RAMacCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AccountStore
    @State private var showsAddAccount = false
    @State private var showsLicense = false
    @State private var pendingRemoval: ManagedAccount?

    var body: some View {
        NavigationSplitView {
            accountShelf
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 350)
        } detail: {
            Group {
                if let account = store.selectedAccount {
                    AccountDetailView(store: store, account: account)
                        .id(account.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RAMPalette.ground)
        }
        .background(RAMPalette.ground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsAddAccount) {
            AddAccountView(store: store)
        }
        .sheet(isPresented: $showsLicense) {
            LicenseNoticeView()
        }
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.title ?? "this account")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("Remove account", role: .destructive) {
                if let pendingRemoval { store.remove(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes the account metadata and its Keychain session from this Mac.")
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            Task { await store.refreshRunningInstances() }
        }
    }

    private var accountShelf: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("RAM")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(RAMPalette.ink)
                    Text("Account shelf")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RAMPalette.muted)
                }
                Spacer()
                Button {
                    showsLicense = true
                } label: {
                    Image(systemName: "info.circle")
                        .accessibilityLabel("License and notices")
                }
                .buttonStyle(.plain)
                .foregroundStyle(RAMPalette.muted)
                Button {
                    showsAddAccount = true
                } label: {
                    Label("Add account", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.top, 17)
            .padding(.bottom, 13)

            TextField("Search accounts", text: $store.search)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RAMPalette.raised)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 9)

            List(selection: $store.selectedID) {
                ForEach(groupNames, id: \.self) { group in
                    Section(group) {
                        ForEach(accounts(in: group)) { account in
                            AccountRow(account: account, isRunning: store.isRunning(account))
                                .tag(account.id)
                                .contextMenu {
                                    Button("Remove account", role: .destructive) {
                                        pendingRemoval = account
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(RAMPalette.shelf)

            HStack {
                Text("\(store.runningAccountIDs.count) running")
                Spacer()
                Text("\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(RAMPalette.muted)
            .padding(.horizontal, 15)
            .frame(height: 33)
        }
        .background(RAMPalette.shelf)
    }

    private var groupNames: [String] {
        Array(Set(store.filteredAccounts.map(\.group))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func accounts(in group: String) -> [ManagedAccount] {
        store.filteredAccounts.filter { $0.group == group }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your account shelf is empty")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Add an account with the Roblox sign-in page. This app keeps the session in Keychain and uses it only for Roblox requests.")
                .font(.system(size: 15))
                .foregroundStyle(RAMPalette.muted)
                .frame(maxWidth: 480, alignment: .leading)
            Button("Add your first account") { showsAddAccount = true }
                .buttonStyle(LaunchButtonStyle())
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(RAMPalette.ink)
    }
}

private struct AccountRow: View {
    let account: ManagedAccount
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 11) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    RAMPalette.raised
                    Text(String(account.username.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(RAMPalette.straw)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(AccountCutShape())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("@\(account.username)")
                    .font(.system(size: 11))
                    .foregroundStyle(RAMPalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isRunning {
                Text("Running")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RAMPalette.straw)
            }
        }
        .padding(.vertical, 4)
    }
}

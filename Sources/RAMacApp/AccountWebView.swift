import RAMacCore
import SwiftUI
import WebKit

struct AccountWebsiteWindow: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    let request: AccountWebsiteRequest
    @StateObject private var model = AccountWebSessionModel()
    @State private var hasLoaded = false

    private var account: ManagedAccount? {
        store.accounts.first(where: { $0.id == request.accountID })
    }

    var body: some View {
        Group {
            if let account {
                VStack(spacing: 0) {
                    identityBar(account)
                    Divider()
                    AccountWebsiteRepresentable(
                        model: model,
                        session: (try? store.sessionCookie(for: account.id)) ?? nil,
                        destination: request.destination.url
                    )
                    .overlay {
                        if model.isLoading {
                            ProgressView().controlSize(.large)
                        } else if let errorMessage = model.errorMessage {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text("Roblox Could Not Load")
                                    .font(.title2.weight(.semibold))
                                Text(errorMessage)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 500)
                                Button("Try Again") { model.reload() }
                            }
                            .padding(28)
                            .background(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                }
                .navigationTitle("Roblox Website as @\(account.username)")
                .toolbar { browserToolbar(account) }
                .confirmationDialog(
                    "Open this link outside Roblox?",
                    isPresented: Binding(
                        get: { model.pendingExternalURL != nil },
                        set: { if !$0 { model.pendingExternalURL = nil } }
                    )
                ) {
                    Button("Open in Default Browser") { model.openPendingExternalURL() }
                    Button("Cancel", role: .cancel) { model.pendingExternalURL = nil }
                } message: {
                    Text("This link is not on roblox.com. It will open without this managed account sign-in.")
                }
                .onDisappear { synchronizeAndClear(account) }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Account Not Found").font(.title2.weight(.semibold))
                    Text("This managed account is no longer available.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private func identityBar(_ account: ManagedAccount) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(account.title).fontWeight(.semibold)
                Text("@\(account.username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("This window uses only this account's temporary Roblox sign-in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private func browserToolbar(_ account: ManagedAccount) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") { model.goBack() }
                .disabled(!model.canGoBack)
            Button("Forward", systemImage: "chevron.right") { model.goForward() }
                .disabled(!model.canGoForward)
            Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Home") { model.load(.home) }
            Button("Profile") { model.load(.profile) }
            Button("Settings") { model.load(.settings) }
            Button("Security") { model.load(.security) }
            Button("Close") {
                synchronizeAndClear(account)
                dismiss()
            }
        }
    }

    private func synchronizeAndClear(_ account: ManagedAccount) {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task {
            let cookie = await model.currentSession()
            await store.synchronizeWebSession(accountID: account.id, cookie: cookie)
            await model.clear()
        }
    }
}

private struct AccountWebsiteRepresentable: NSViewRepresentable {
    @ObservedObject var model: AccountWebSessionModel
    let session: String?
    let destination: URL

    func makeNSView(context: Context) -> NSView {
        guard let session, !session.isEmpty else {
            let label = NSTextField(labelWithString: "This account is signed out. Close this window and use Sign In Again.")
            label.alignment = .center
            return label
        }
        return model.configure(session: session, destination: destination)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

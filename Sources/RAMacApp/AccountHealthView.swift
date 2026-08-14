import RAMacCore
import SwiftUI

struct AccountHealthRow: View {
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    @State private var showsSignIn = false

    var body: some View {
        HStack(spacing: 10) {
            Label(statusText, systemImage: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityLabel("Account status: \(statusText)")
            Spacer()
            Button("Check Account") { Task { await store.checkAccount(account) } }
                .disabled(isChecking)
            if needsSignIn {
                Button("Sign In Again") { showsSignIn = true }
            }
        }
        .sheet(isPresented: $showsSignIn) {
            AccountReauthenticationView(store: store, account: account)
        }
    }

    private var health: AccountHealth { store.accountHealth[account.id] ?? .unchecked }
    private var isChecking: Bool { if case .checking = health { return true }; return false }
    private var needsSignIn: Bool {
        switch health { case .signedOut, .wrongAccount: return true; default: return false }
    }
    private var statusText: String {
        switch health {
        case .unchecked: return "Not checked"
        case .checking: return "Checking"
        case .ready(let date): return "Ready, checked \(date.formatted(date: .omitted, time: .shortened))"
        case .signedOut: return "Signed out"
        case .wrongAccount: return "Different account detected"
        case .networkUnavailable: return "Could not check"
        }
    }
    private var statusSymbol: String {
        switch health {
        case .ready: return "checkmark.circle"
        case .signedOut, .wrongAccount: return "exclamationmark.triangle"
        case .checking: return "arrow.clockwise"
        case .networkUnavailable: return "wifi.exclamationmark"
        case .unchecked: return "questionmark.circle"
        }
    }
    private var statusColor: Color {
        switch health {
        case .signedOut, .wrongAccount: return .red
        default: return .secondary
        }
    }
}

private struct AccountReauthenticationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    let account: ManagedAccount
    @StateObject private var browser = LoginBrowserModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in as @\(account.username). Only the saved Roblox sign-in will change. The account name, groups, notes, favorite games, and Launch Sets will stay the same.")
                    .foregroundStyle(.secondary)
                ZStack {
                    RobloxLoginWebView(model: browser)
                    if browser.isLoading { ProgressView().controlSize(.large) }
                }
                .appRoundedPanel()
                HStack {
                    Text(browser.hasSession ? "Ready to save" : "Sign in above to continue")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save and Continue") {
                        Task {
                            guard let cookie = await browser.sessionCookie() else { return }
                            if await store.replaceSession(cookie, for: account) { dismiss() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!browser.hasSession)
                }
            }
            .padding(.horizontal, AppGeometry.windowEdgeControlInset)
            .padding(.top, AppGeometry.windowContentInset)
            .padding(.bottom, AppGeometry.windowEdgeControlInset)
            .navigationTitle("Sign In Again as @\(account.username)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            browser.updateSessionState()
        }
    }
}

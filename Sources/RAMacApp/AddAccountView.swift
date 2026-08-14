import SwiftUI

struct AddAccountView: View {
    enum Method: String, CaseIterable, Identifiable {
        case browser = "Sign In on Roblox"
        case cookie = "Paste Session Value"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    @StateObject private var browser = LoginBrowserModel()
    @State private var method: Method = .browser
    @State private var cookie = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Sign-in method") {
                    Picker("Sign-in method", selection: $method) {
                        ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .frame(maxWidth: 430)

                if method == .browser {
                    browserSignIn
                } else {
                    cookieImport
                }
            }
            .padding(.horizontal, AppGeometry.windowEdgeControlInset)
            .padding(.top, AppGeometry.windowContentInset)
            .padding(.bottom, AppGeometry.windowEdgeControlInset)
            .navigationTitle("Add Roblox Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(
            minWidth: method == .browser ? 820 : 620,
            minHeight: method == .browser ? 620 : 300
        )
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if method == .browser { browser.updateSessionState() }
        }
    }

    private var browserSignIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use the Roblox page below to sign in. When the page is ready, select Save This Account. The app saves the Roblox sign-in in Keychain, the private password storage built into macOS. It never sees or saves your password.")
                .foregroundStyle(.secondary)

            ZStack {
                RobloxLoginWebView(model: browser)
                if browser.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .appRoundedPanel()

            HStack {
                Label(
                    browser.hasSession ? "Ready to save" : "Sign in above to continue",
                    systemImage: browser.hasSession ? "checkmark.circle.fill" : "person.crop.circle"
                )
                .foregroundStyle(browser.hasSession ? .green : .secondary)
                Spacer()
                Button(store.isWorking ? "Saving" : "Save This Account") {
                    Task {
                        guard let sessionCookie = await browser.sessionCookie() else { return }
                        if await store.importSession(sessionCookie) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!browser.hasSession || store.isWorking)
            }
        }
    }

    private var cookieImport: some View {
        Form {
            Section("Advanced: Paste a Roblox Session") {
                SecureField(".ROBLOSECURITY value", text: $cookie)
                Text("Most people should use Sign In on Roblox. Use this option only if you already know how to copy the .ROBLOSECURITY value from an account you own. This value can access the account. Protect it like a password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(store.isWorking ? "Checking" : "Check and Save Account") {
                    Task {
                        if await store.importSession(cookie) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI

struct AddAccountView: View {
    enum Method: String, CaseIterable, Identifiable {
        case browser = "Browser Sign-In"
        case cookie = "Session Cookie"
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
            .padding(20)
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
            Text("Sign in on Roblox. The browser session is temporary. The accepted account session moves to this Mac's Keychain.")
                .foregroundStyle(.secondary)

            ZStack {
                RobloxLoginWebView(model: browser)
                if browser.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            HStack {
                Label(
                    browser.hasSession ? "Signed-in session found" : "Sign in above to continue",
                    systemImage: browser.hasSession ? "checkmark.circle.fill" : "person.crop.circle"
                )
                .foregroundStyle(browser.hasSession ? .green : .secondary)
                Spacer()
                Button(store.isWorking ? "Adding" : "Add Signed-In Account") {
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
            Section("Session Cookie") {
                SecureField(".ROBLOSECURITY value", text: $cookie)
                Text("Paste only a session that belongs to you. Treat this value like a password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(store.isWorking ? "Checking" : "Check and Add") {
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

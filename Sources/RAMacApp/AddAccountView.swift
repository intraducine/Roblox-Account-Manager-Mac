import SwiftUI

struct AddAccountView: View {
    enum Method: String, CaseIterable, Identifiable {
        case browser = "Sign In on Roblox"
        case cookie = "Paste .ROBLOSECURITY"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @StateObject private var browser = LoginBrowserModel()
    @State private var method: Method = .browser
    @State private var cookie = ""
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?

    private var isSaving: Bool { saveTask != nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Sign-in method", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.large)
                .fixedSize()
                .disabled(isSaving)

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
        .frame(minWidth: 820, minHeight: 620)
        .onChange(of: method) { _ in
            saveError = nil
            cookie = ""
        }
        .onDisappear {
            saveTask?.cancel()
            saveError = nil
            cookie = ""
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if method == .browser { browser.updateSessionState() }
        }
    }

    private var browserSignIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in below, then select Save This Account. For passkeys, sign in with your regular browser and use Paste .ROBLOSECURITY here.")
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
                Button(isSaving ? "Saving…" : "Save This Account") {
                    saveAccount { await browser.sessionCookie() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!browser.hasSession || isSaving || store.isWorking)
            }
        }
    }

    private var cookieImport: some View {
        Form {
            Section("Roblox session") {
                SecureField(".ROBLOSECURITY value", text: $cookie, prompt: Text("Paste the value here"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSaving)
                Text("Use a session value from your own Roblox account. Protect it like a password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(isSaving ? "Checking…" : "Check and Save Account") {
                    let value = cookie
                    saveAccount { value }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || store.isWorking)
            }
        }
        .formStyle(.grouped)
    }

    private func saveAccount(_ session: @escaping @MainActor () async -> String?) {
        guard !isSaving, !store.isWorking else { return }
        saveError = nil
        saveTask = Task {
            defer { saveTask = nil }
            do {
                guard let value = await session() else {
                    if !Task.isCancelled { saveError = "Sign in on Roblox, then try again." }
                    return
                }
                try Task.checkCancellation()
                try await store.importSession(value)
                cookie = ""
                openWindow(id: "accounts")
                dismiss()
            } catch {
                if !Task.isCancelled { saveError = error.localizedDescription }
            }
        }
    }
}

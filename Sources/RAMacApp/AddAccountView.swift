import SwiftUI

struct AddAccountView: View {
    enum Method: String, CaseIterable, Identifiable {
        case browser = "Browser sign-in"
        case cookie = "Session cookie"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    @StateObject private var browser = LoginBrowserModel()
    @State private var method: Method = .browser
    @State private var cookie = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a Roblox account")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("The session stays in this Mac's Keychain.")
                        .foregroundStyle(RAMPalette.muted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }

            Picker("Add method", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            if method == .browser {
                VStack(alignment: .leading, spacing: 10) {
                    RobloxLoginWebView(model: browser)
                        .frame(minWidth: 760, minHeight: 470)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    HStack {
                        Text(browser.hasSession ? "A signed-in Roblox session is ready." : "Sign in above, then add the signed-in account.")
                            .font(.system(size: 12))
                            .foregroundStyle(browser.hasSession ? RAMPalette.straw : RAMPalette.muted)
                        Spacer()
                        Button(store.isWorking ? "Adding account" : "Add signed-in account") {
                            Task {
                                guard let sessionCookie = await browser.sessionCookie() else { return }
                                if await store.importSession(sessionCookie) { dismiss() }
                            }
                        }
                        .buttonStyle(LaunchButtonStyle())
                        .disabled(!browser.hasSession || store.isWorking)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste only a session that belongs to you. Never send this value to another person.")
                        .foregroundStyle(RAMPalette.muted)
                    SecureField(".ROBLOSECURITY value", text: $cookie)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button(store.isWorking ? "Checking session" : "Check and add") {
                            Task {
                                if await store.importSession(cookie) { dismiss() }
                            }
                        }
                        .buttonStyle(LaunchButtonStyle())
                        .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    }
                }
                .frame(minWidth: 640, minHeight: 220, alignment: .top)
            }
        }
        .padding(24)
        .background(RAMPalette.ground)
        .foregroundStyle(RAMPalette.ink)
        .preferredColorScheme(.dark)
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if method == .browser { browser.updateSessionState() }
        }
    }
}

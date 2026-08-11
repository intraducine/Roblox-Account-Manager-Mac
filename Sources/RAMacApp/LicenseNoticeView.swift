import SwiftUI

struct LicenseNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("What This App Does") {
                    Text("Save several Roblox accounts and keep them open at the same time.")
                    Text("Open Roblox from Applications for one normal account. Use this manager for accounts that must stay open together.")
                }

                Section("Accounts and Privacy") {
                    Text("The app saves each Roblox sign-in in macOS Keychain, the secure password storage built into your Mac. It never stores your Roblox password.")
                    Text("Account names, groups, notes, and launch choices stay on this Mac. At launch, the app sends the saved sign-in only to Roblox.")
                }

                Section("How Accounts Run Together") {
                    Text("Each account opens in its own unchanged copy of the Roblox app on your Mac. This lets you launch another account without closing the first one.")
                    Text("An advanced fallback changes the Roblox copy. Roblox may treat it as modified, so the app warns you before you can use it.")
                }

                Section("Project and License") {
                    LabeledContent("Version", value: releaseVersion)
                    Text("This app is based on Roblox Account Manager by ic3w0lf22 and its contributors. Roblox Corporation does not make or approve it. Roblox is a trademark of Roblox Corporation.")
                    Text("GNU GPL version 3 lets you inspect, share, and change the source code. The software has no warranty.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("About This App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 760, height: 680)
    }

    private var releaseVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        default:
            return "Development build"
        }
    }
}

import SwiftUI

struct LicenseNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var updater: SoftwareUpdateController

    var body: some View {
        NavigationStack {
            Form {
                Section("Start Here") {
                    Text("1. Select Add Account and sign in on Roblox.")
                    Text("2. Use the checkboxes in the account list to select every account that you want to open.")
                    Text("3. Choose a recent game or enter its Place ID, choose a server, and select Launch Accounts.")
                    Text("Open Roblox.app directly when you only need one account. Use this manager when you want a saved account or several Roblox windows at once.")
                }

                Section("Words Used in the App") {
                    Text("A Place ID is the number after /games/ in a Roblox game link. It tells the app which game to open.")
                    Text("A Launch Set is a saved shortcut for a group of accounts, one game, and one server choice.")
                    Text("A Job ID is a temporary code for one running server. Most users do not need to enter one.")
                }

                Section("Accounts and Privacy") {
                    Text("The app saves each Roblox sign-in in Keychain, the private password storage built into macOS. It never sees or saves your Roblox password.")
                    Text("Account names, groups, notes, and launch choices stay on this Mac. When you launch, the app sends the saved sign-in only to Roblox.")
                }

                Section("How Accounts Run Together") {
                    Text("Each account opens in its own copy of Roblox. The recommended method does not change any Roblox file and keeps Roblox Corporation's original signature.")
                    Text("The advanced fallback changes the copied app and gives it a new signature. Roblox can detect this, so the app warns you before it can be used.")
                }

                Section("Project and License") {
                    LabeledContent("Version", value: releaseVersion)
                    Text("This app is based on Roblox Account Manager by ic3w0lf22 and its contributors. Roblox Corporation does not make or approve it. Roblox is a trademark of Roblox Corporation.")
                    Text("GNU GPL version 3 lets you inspect, share, and change the source code. The software has no warranty.")
                }

                Section("Software Updates") {
                    Text("Check the public GitHub release page from inside the app. A new release is downloaded, checked, installed, and opened only after you approve it.")
                    Button("Check for Updates") {
                        dismiss()
                        openWindow(id: "software-update")
                    }
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

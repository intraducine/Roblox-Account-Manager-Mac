import SwiftUI

struct LicenseNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Roblox Account Manager for Mac") {
                    Text("Free software under GNU GPL version 3. This is a new Mac port based on the Roblox Account Manager project by ic3w0lf22 and contributors.")
                    Text("There is no warranty. You can share and change the program under the license terms.")
                        .foregroundStyle(.secondary)
                }

                Section("Source Code") {
                    Link(
                        "Open Mac Source",
                        destination: URL(string: "https://github.com/intraducine/Roblox-Account-Manager-Mac")!
                    )
                    Link(
                        "Open Original Project",
                        destination: URL(string: "https://github.com/ic3w0lf22/Roblox-Account-Manager")!
                    )
                }

                Section("Launch Modes") {
                    Text("Official Roblox is the default. It uses /Applications/Roblox.app without copying, editing, or signing it.")
                    Text("Modified Parallel Fallback can run more than one account. It changes and signs managed copies. Roblox says modified clients are not allowed.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Roblox is a trademark of Roblox Corporation. This project is not made by or approved by Roblox Corporation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 560, height: 620)
    }
}

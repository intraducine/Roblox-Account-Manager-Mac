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

                Section("Managed Roblox Clients") {
                    Text("The manager always prepares a separate Roblox client. This lets you start another managed account without closing the first one.")
                    Text("Normal launches use byte-identical copies of /Applications/Roblox.app. They keep Roblox's original bundle files and signature.")
                    Text("The advanced modified fallback changes bundle settings and signs each copy again. Roblox says modified clients are not allowed.")
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
        .frame(width: 640, height: 620)
    }
}

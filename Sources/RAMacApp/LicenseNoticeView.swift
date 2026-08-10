import SwiftUI

struct LicenseNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("License and notices")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }
            Text("Roblox Account Manager for Mac is free software under GNU GPL version 3. It is a new Mac port based on the Roblox Account Manager project by ic3w0lf22 and contributors.")
            Text("There is no warranty. You can share and change the program under the license terms. The complete license and source code are in the repository.")
                .foregroundStyle(RAMPalette.muted)
            HStack(spacing: 10) {
                Button("Open Mac source") {
                    openURL(URL(string: "https://github.com/intraducine/Roblox-Account-Manager-Mac")!)
                }
                Button("Open original project") {
                    openURL(URL(string: "https://github.com/ic3w0lf22/Roblox-Account-Manager")!)
                }
            }
            .buttonStyle(QuietButtonStyle())
            Spacer()
            Text("Roblox is a trademark of Roblox Corporation. This project is not made by or approved by Roblox Corporation.")
                .font(.system(size: 11))
                .foregroundStyle(RAMPalette.muted)
        }
        .padding(24)
        .frame(width: 560, height: 320)
        .background(RAMPalette.ground)
        .foregroundStyle(RAMPalette.ink)
        .preferredColorScheme(.dark)
    }
}

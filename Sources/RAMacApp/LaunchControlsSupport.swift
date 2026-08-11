import RAMacCore
import SwiftUI

func placeIDBindingResettingServer(
    placeID: Binding<String>,
    serverSelection: Binding<RobloxServerSelection>
) -> Binding<String> {
    Binding(
        get: { placeID.wrappedValue },
        set: { newValue in
            let current = placeID.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != next {
                serverSelection.wrappedValue = .automatic
            }
            placeID.wrappedValue = newValue
        }
    )
}

struct LaunchClientNotice: View {
    @ObservedObject var store: AccountStore
    let onRequestModifiedFallback: () -> Void
    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isModified ? "exclamationmark.triangle" : "checkmark.shield")
                .foregroundStyle(isModified ? Color.orange : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(isModified ? "Advanced fallback is active" : "Recommended launch method")
                    .fontWeight(.semibold)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isModified {
                Button("Use Recommended Method") { store.setLaunchMode(.unmodifiedParallel) }
                    .disabled(store.isWorking || store.isBatchLaunching || !store.runningAccountIDs.isEmpty)
            }

            Button("How Launching Works") { showsDetails = true }
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    details
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var isModified: Bool {
        store.launchMode == .modifiedParallel
    }

    private var summary: String {
        if isModified {
            return "This option changes the Roblox copy. Roblox may treat it as a modified client."
        }
        return "Each account opens in a separate, unchanged copy of your installed Roblox app."
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Accounts Run Together")
                .font(.headline)

            Text("Every account you launch here opens in its own Roblox app copy. This lets you keep several accounts open at the same time.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended method")
                    .fontWeight(.semibold)
                Text("The manager copies the Roblox app already installed on your Mac without changing its files. macOS still verifies the copy as the official Roblox app. The manager uses this method unless you choose the advanced fallback.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced fallback")
                    .fontWeight(.semibold)
                Text("Use this only if the recommended method stops working. It changes how macOS identifies each copy. Roblox may treat the changed copy as a modified client, which can put an account at risk.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isModified {
                Button("Show Advanced Fallback Warning…") {
                    showsDetails = false
                    onRequestModifiedFallback()
                }
            }
        }
        .frame(width: 420)
        .padding(18)
    }
}

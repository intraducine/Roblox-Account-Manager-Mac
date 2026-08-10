import RAMacCore
import SwiftUI

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
                Text(isModified ? "Modified fallback is active" : "Unmodified Roblox copies")
                    .fontWeight(.semibold)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isModified {
                Button("Use Unmodified") { store.setLaunchMode(.unmodifiedParallel) }
                    .disabled(store.isWorking || store.isBatchLaunching || !store.runningAccountIDs.isEmpty)
            }

            Button("How This Works") { showsDetails = true }
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
            return "This fallback changes bundle settings and signs each copy again. Roblox may detect it."
        }
        return "Exact copies keep Roblox's original files and signature."
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parallel Roblox Launch")
                .font(.headline)

            Text("The manager uses an exact Roblox copy even when you start one account. This keeps that client separate, so you can start another managed account later without closing the first one.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unmodified")
                    .fontWeight(.semibold)
                Text("The copy matches /Applications/Roblox.app byte for byte and keeps Roblox's original signature. This is the normal mode.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Modified fallback")
                    .fontWeight(.semibold)
                Text("The manager changes bundle settings and signs the copy again. Use this only if Roblox stops the unmodified method from working.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isModified {
                Button("Advanced: Try Modified Fallback…") {
                    showsDetails = false
                    onRequestModifiedFallback()
                }
            }
        }
        .frame(width: 420)
        .padding(18)
    }
}

struct ServerTargetHelpButton: View {
    @State private var showsHelp = false

    var body: some View {
        Button {
            showsHelp = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .help("Explain the optional server field")
        .accessibilityLabel("About specific servers")
        .sheet(isPresented: $showsHelp) {
            ServerTargetHelpSheet()
        }
    }
}

private struct ServerTargetHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Specific Server")
                .font(.title2.weight(.semibold))

            Text("Leave this field empty to join a normal public server.")

            Text("A Job ID identifies one running public server. Use it only when you want every selected account to join that exact server. It is not the Place ID.")

            Text("You can also paste a complete Roblox private server link here.")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

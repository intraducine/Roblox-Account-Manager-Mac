import SwiftUI

struct BatchLaunchDock: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var server: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Launch \(selectionCount) account\(selectionCount == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .bold))
                Text(store.batchStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RAMPalette.muted)
                Spacer()
                Text("One shared destination")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RAMPalette.straw)
                    .padding(.trailing, 22)
            }

            HStack(alignment: .bottom, spacing: 12) {
                launchField("Place ID", text: $placeID, prompt: "920587237")
                    .frame(minWidth: 170, maxWidth: 230)
                launchField("Job ID or private server link", text: $server, prompt: "Optional")
                Button(store.isBatchLaunching ? "Starting accounts" : buttonTitle) {
                    Task { await store.launchBatch(placeText: placeID, serverText: server) }
                }
                .buttonStyle(LaunchButtonStyle())
                .disabled(store.isBatchLaunching)
            }
            .disabled(store.isBatchLaunching)
        }
        .padding(.leading, 21)
        .padding(.trailing, 28)
        .padding(.vertical, 18)
        .background(RAMPalette.raised)
        .clipShape(LaunchDockShape())
        .accessibilityElement(children: .contain)
    }

    private var selectionCount: Int {
        store.batchSelectedIDs.count
    }

    private var buttonTitle: String {
        let hasFailures = store.batchStates.values.contains {
            if case .failed = $0 { return true }
            return false
        }
        return hasFailures ? "Retry \(selectionCount) now" : "Launch \(selectionCount) now"
    }

    private func launchField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RAMPalette.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RAMPalette.ground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

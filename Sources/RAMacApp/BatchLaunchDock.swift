import RAMacCore
import SwiftUI

struct BatchLaunchBar: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var serverSelection: RobloxServerSelection
    let onRequestModifiedFallback: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Batch Launch", systemImage: "person.2.fill")
                    .fontWeight(.semibold)
                Text("\(selectionCount) account\(selectionCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.batchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LaunchClientNotice(
                store: store,
                onRequestModifiedFallback: onRequestModifiedFallback
            )

            HStack(spacing: 10) {
                TextField("Shared place ID", text: $placeID)
                    .frame(width: 180)
                ServerSelectionControl(
                    store: store,
                    placeID: $placeID,
                    selection: $serverSelection,
                    requiredSpaces: max(1, selectionCount)
                )
                Button(store.isBatchLaunching ? "Starting" : buttonTitle) {
                    Task { await store.launchBatch(placeText: placeID, server: serverSelection) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBatchLaunching)
            }
            .controlSize(.large)
            .disabled(store.isBatchLaunching)
        }
        .padding(14)
        .background(.bar)
    }

    private var selectionCount: Int {
        store.batchSelectedIDs.count
    }

    private var buttonTitle: String {
        let hasFailures = store.batchStates.values.contains {
            if case .failed = $0 { return true }
            return false
        }
        return hasFailures ? "Retry \(selectionCount)" : "Launch \(selectionCount)"
    }
}

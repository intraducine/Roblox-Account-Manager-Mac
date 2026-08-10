import SwiftUI

struct BatchLaunchBar: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var server: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Batch Launch", systemImage: "person.2.fill")
                    .fontWeight(.semibold)
                Text("\(selectionCount) account\(selectionCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Text("· \(store.launchMode.shortTitle)")
                    .foregroundStyle(store.launchMode == .modifiedParallel ? Color.orange : .secondary)
                Spacer()
                Text(store.batchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Shared place ID", text: $placeID)
                    .frame(width: 180)
                TextField("Shared job ID or private server link", text: $server)
                Button(store.isBatchLaunching ? "Starting" : buttonTitle) {
                    Task { await store.launchBatch(placeText: placeID, serverText: server) }
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

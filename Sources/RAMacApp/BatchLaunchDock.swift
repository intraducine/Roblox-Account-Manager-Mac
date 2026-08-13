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
                Label("Selected Accounts", systemImage: "person.2.fill")
                    .fontWeight(.semibold)
                Text("\(selectionCount) account\(selectionCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.batchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(store.isOpeningSelectedApps ? "Opening Apps" : "Open Roblox Apps") {
                    Task { await store.launchSelectedApps() }
                }
                .buttonStyle(.borderless)
                .disabled(store.isBatchLaunching || store.isOpeningSelectedApps || store.isWorking)
                .help("Open the Roblox app for every selected account without joining a game")
            }

            LaunchClientNotice(
                store: store,
                onRequestModifiedFallback: onRequestModifiedFallback
            )

            HStack(spacing: 10) {
                TextField("Place ID for all", text: gamePlaceID)
                    .frame(width: 180)
                    .help("The Place ID is the number after /games/ in a Roblox game link")
                ExperienceChooserButton(store: store, placeID: gamePlaceID)
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
                .disabled(store.isBatchLaunching || store.isOpeningSelectedApps)
            }
            .controlSize(.large)
            .disabled(store.isBatchLaunching || store.isOpeningSelectedApps)
        }
        .padding(14)
        .background(.bar)
    }

    private var selectionCount: Int {
        store.batchSelectedIDs.count
    }

    private var gamePlaceID: Binding<String> {
        placeIDBindingResettingServer(
            placeID: $placeID,
            serverSelection: $serverSelection
        )
    }

    private var buttonTitle: String {
        let hasFailures = store.batchStates.values.contains {
            if case .failed = $0 { return true }
            return false
        }
        return hasFailures
            ? "Retry \(selectionCount) Account\(selectionCount == 1 ? "" : "s")"
            : "Launch \(selectionCount) Account\(selectionCount == 1 ? "" : "s")"
    }
}

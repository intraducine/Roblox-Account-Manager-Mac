import RAMacCore
import SwiftUI

struct BatchLaunchBar: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var serverSelection: RobloxServerSelection
    let onRequestModifiedFallback: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Launch Multiple Accounts")
                        .font(.title2.weight(.semibold))
                    Text("\(selectionCount) selected: \(selectedHandles)")
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Choose what all selected accounts should open.")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(spacing: 0) {
                        appOnlyRow
                            .padding(.vertical, 8)

                        Divider()

                        HStack {
                            Text("Game")
                            Spacer(minLength: 24)
                            ExperienceChooserButton(store: store, placeID: gamePlaceID)
                        }
                        .padding(.vertical, 8)

                        Divider()

                        HStack {
                            Text("Server")
                            Spacer(minLength: 24)
                            ServerSelectionControl(
                                store: store,
                                placeID: $placeID,
                                selection: $serverSelection,
                                requiredSpaces: max(1, selectionCount)
                            )
                        }
                        .padding(.vertical, 8)

                        Divider()

                        launchRow
                            .padding(.vertical, 8)

                        if store.launchMode == .modifiedParallel {
                            Divider()

                            LaunchClientNotice(
                                store: store,
                                onRequestModifiedFallback: onRequestModifiedFallback
                            )
                            .padding(.vertical, 8)
                        }

                        Divider()

                        AdvancedLaunchOptions(
                            store: store,
                            placeID: gamePlaceID,
                            onRequestModifiedFallback: onRequestModifiedFallback
                        )
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 4)
                } label: {
                    Text("Open Roblox")
                        .font(.headline)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .navigationTitle("Launch Multiple Accounts")
    }

    private var appOnlyRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open the apps only")
                    .fontWeight(.medium)
                Text("Open each selected account without joining a game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.isOpeningSelectedApps ? "Opening Apps" : "Open Roblox Apps") {
                Task { await store.launchSelectedApps() }
            }
            .disabled(store.isBatchLaunching || store.isOpeningSelectedApps || store.isWorking)
        }
    }

    private var launchRow: some View {
        HStack {
            Text(batchLaunchSummary)
                .foregroundStyle(.secondary)
            Spacer()
            Button(store.isBatchLaunching ? "Starting" : buttonTitle) {
                Task { await store.launchBatch(placeText: placeID, server: serverSelection) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                store.isBatchLaunching
                    || store.isOpeningSelectedApps
                    || numericPlaceID == nil
            )
        }
    }

    private var selectionCount: Int {
        store.batchSelectedIDs.count
    }

    private var selectedHandles: String {
        store.accounts
            .filter { store.batchSelectedIDs.contains($0.id) }
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            .map { "@\($0.username)" }
            .joined(separator: ", ")
    }

    private var batchLaunchSummary: String {
        if numericPlaceID == nil {
            return "Choose a game to continue"
        }
        if store.isBatchLaunching || store.isOpeningSelectedApps || !store.batchStates.isEmpty {
            return store.batchStatus
        }
        return "Starts the selected accounts with the game and server above"
    }

    private var gamePlaceID: Binding<String> {
        placeIDBindingResettingServer(
            placeID: $placeID,
            serverSelection: $serverSelection
        )
    }

    private var numericPlaceID: Int64? {
        guard let value = Int64(placeID.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
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

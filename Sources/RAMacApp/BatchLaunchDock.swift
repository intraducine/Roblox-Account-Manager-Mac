import RAMacCore
import SwiftUI

struct BatchLaunchBar: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @Binding var serverSelection: RobloxServerSelection
    let onRequestModifiedFallback: () -> Void
    @State private var showsSaveLaunchSet = false
    @State private var launchSetName = ""
    @State private var pinsLaunchSet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(selectionCount) selected: \(selectedHandles)")
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                let accountsWithIssues = selectedAccounts.filter { store.batchStates[$0.id]?.healthMessage != nil }
                if store.batchPausedForReview {
                    BatchReadinessView(store: store)
                } else if !accountsWithIssues.isEmpty {
                    GroupBox("Check these accounts") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(accountsWithIssues) { account in
                                BatchAccountIssueRow(store: store, account: account)
                            }
                        }
                        .padding(8)
                    }
                }

                GroupBox {
                    VStack(spacing: 0) {
                        appOnlyRow
                            .padding(.vertical, 8)

                        Divider()

                        HStack {
                            Text("Shared Game")
                            Spacer(minLength: 24)
                            ExperienceChooserButton(store: store, placeID: gamePlaceID)
                        }
                        .padding(.vertical, 8)

                        if usesSharedGame {
                            Divider()

                            HStack {
                                Text("Shared Server")
                                Spacer(minLength: 24)
                                ServerSelectionControl(
                                    store: store,
                                    placeID: $placeID,
                                    selection: $serverSelection,
                                    requiredSpaces: max(1, sharedAccountCount)
                                )
                            }
                            .padding(.vertical, 8)
                        }

                        Divider()

                        launchSettingsRow
                            .padding(.vertical, 8)

                        Divider()

                        FullWidthDisclosure("Window Layout") {
                            windowArrangementRow
                        }
                        .padding(.vertical, 8)

                        Divider()

                        FullWidthDisclosure("Per-Account Options") {
                            AccountLaunchOptions(
                                store: store, accounts: selectedAccounts, hasSharedGame: numericPlaceID != nil,
                                defaults: store.batchLaunchSettingsOverride ?? store.launchSettings,
                                games: $store.batchAccountGames, settings: $store.batchAccountSettings
                            )
                        }
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
                    .padding(.horizontal, AppGeometry.panelEdgeControlInset)
                } label: {
                    Text("Launch Options")
                        .font(.headline)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .navigationTitle("Launch Multiple Accounts")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            launchRow
                .frame(maxWidth: 760)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .sheet(isPresented: $showsSaveLaunchSet) {
            saveLaunchSetSheet
        }
        .sheet(isPresented: $store.showsBatchPublicServers) {
            if let numericPlaceID {
                NavigationStack {
                    PublicServerListView(
                        store: store, placeID: numericPlaceID,
                        requiredSpaces: max(1, sharedAccountCount)
                    ) { server in
                        serverSelection = server
                        store.showsBatchPublicServers = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { store.showsBatchPublicServers = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                }
                .frame(width: 680, height: 560)
            }
        }
    }

    private var appOnlyRow: some View {
        HStack {
            Text("Open Roblox without joining a game.")
            Spacer()
            Button(store.isOpeningSelectedApps ? "Opening Apps" : "Open Roblox Apps") {
                Task { await store.launchSelectedApps() }
            }
            .disabled(store.isBatchLaunching || store.isOpeningSelectedApps || store.isWorking)
        }
    }

    private var windowArrangementRow: some View {
        InlineWindowArrangementEditor(
            controller: store.windowLayout,
            accounts: selectedAccounts,
            assignments: effectiveWindowAssignments,
            usesSavedPlacements: store.batchWindowArrangement.usesSavedPlacements,
            customStatus: "Using a custom window arrangement for this launch.",
            disabled: store.isBatchLaunching || store.isOpeningSelectedApps || store.isWorking,
            onAssignmentsChange: { assignments in
                store.batchWindowArrangement = .custom(assignments)
            },
            onUseSavedPlacements: {
                store.batchWindowArrangement = .savedPlacements
            }
        )
    }

    private var launchSettingsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Graphics and sound")
                .fontWeight(.medium)
            LaunchSettingsOverrideEditor(
                defaults: store.launchSettings,
                overrideSettings: $store.batchLaunchSettingsOverride,
                customDescription: "Using custom settings for this launch."
            )
        }
        .disabled(store.isBatchLaunching || store.isOpeningSelectedApps || store.isWorking)
    }

    private var launchRow: some View {
        HStack(spacing: 12) {
            if let batchLaunchSummary {
                Text(batchLaunchSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Save as Launch Set…") {
                launchSetName = ""
                pinsLaunchSet = false
                showsSaveLaunchSet = true
            }
            Button(store.isBatchLaunching ? "Starting…" : buttonTitle) {
                Task { await store.launchBatch(placeText: placeID, server: serverSelection) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedAccounts.contains {
                store.batchStates[$0.id]?.healthMessage != nil && store.accountHealth[$0.id]?.needsSignIn == true
            })
        }
        .disabled(store.isBusyWithRoblox || !hasGames)
    }

    private var saveLaunchSetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Launch Set").font(.headline)
            TextField("Name", text: $launchSetName)
            Toggle("Pin in the Accounts sidebar", isOn: $pinsLaunchSet)
            if usesSharedGame {
                switch serverSelection {
                case .publicInstance, .manualJob:
                    Text("Choose a public server each time you run this set.").foregroundStyle(.secondary)
                case .player:
                    Text("Choose a player each time you run this set.").foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showsSaveLaunchSet = false }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if store.saveBatchAsLaunchSet(name: launchSetName, placeID: numericPlaceID, pinned: pinsLaunchSet) {
                        showsSaveLaunchSet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(launchSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 405)
    }

    private var selectionCount: Int {
        store.batchSelectedIDs.count
    }

    private var selectedAccounts: [ManagedAccount] {
        store.accounts.filter { store.batchSelectedIDs.contains($0.id) }
    }

    private var effectiveWindowAssignments: [WindowLayoutAssignment] {
        store.batchWindowArrangement.effectiveAssignments(
            savedAssignments: store.windowLayout.savedAssignments(for: store.batchSelectedIDs),
            accountIDs: store.batchSelectedIDs
        )
    }

    private var selectedHandles: String {
        store.accounts
            .filter { store.batchSelectedIDs.contains($0.id) }
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            .map { "@\($0.username)" }
            .joined(separator: ", ")
    }

    private var batchLaunchSummary: String? {
        if !hasGames {
            return "Choose a shared game or a game for each account."
        }
        if store.isBatchLaunching || store.isOpeningSelectedApps || !store.batchStates.isEmpty {
            return store.batchStatus
        }
        return nil
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

    private var sharedAccountCount: Int {
        selectedAccounts.filter { (store.batchAccountGames[$0.id]?.placeID ?? 0) <= 0 }.count
    }

    private var usesSharedGame: Bool { numericPlaceID != nil && sharedAccountCount > 0 }

    private var hasGames: Bool {
        selectionCount > 0 && (numericPlaceID != nil
            || LaunchSetGame.covers(store.batchSelectedIDs, games: store.batchAccountGames))
    }

    private var buttonTitle: String {
        let hasFailures = store.batchStates.values.contains { $0.errorMessage != nil }
        return hasFailures
            ? "Retry \(selectionCount) Account\(selectionCount == 1 ? "" : "s")"
            : "Launch \(selectionCount) Account\(selectionCount == 1 ? "" : "s")"
    }
}

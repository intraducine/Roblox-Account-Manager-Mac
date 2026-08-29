import AppKit
import RAMacCore
import SwiftUI

private enum WindowControlSpacing {
    static let contentInset: CGFloat = 12
}

struct InlineWindowArrangementEditor: View {
    @ObservedObject var controller: WindowLayoutController
    let accounts: [ManagedAccount]
    let assignments: [WindowLayoutAssignment]
    let usesSavedPlacements: Bool
    let customStatus: String
    let disabled: Bool
    let onAssignmentsChange: ([WindowLayoutAssignment]) -> Void
    let onUseSavedPlacements: () -> Void

    @State private var selectedAccountID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window arrangement")
                        .fontWeight(.medium)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if !assignments.isEmpty {
                        Button("Clear Placements") {
                            onAssignmentsChange([])
                        }
                        .fixedSize()
                    }
                    if !usesSavedPlacements {
                        Button("Use Saved Arrangement") {
                            guard controller.ensureAccessibilityPermission() else { return }
                            onUseSavedPlacements()
                        }
                        .fixedSize()
                    }
                }
            }

            if !accounts.isEmpty {
                Text("Choose a quick layout, or select a profile and choose its place on a display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Arrange Automatically") {
                        guard controller.ensureAccessibilityPermission() else { return }
                        guard let planned = WindowArrangementPlanner.automaticAssignments(
                            accountIDs: accountIDs,
                            displays: controller.displays
                        ) else { return }
                        selectedAccountID = nil
                        onAssignmentsChange(planned)
                    }
                    .disabled(!canArrangeAutomatically)
                    .help(automaticArrangementHelp)

                    Button("Full Screen All") {
                        guard controller.ensureAccessibilityPermission() else { return }
                        selectedAccountID = nil
                        onAssignmentsChange(
                            WindowArrangementPlanner.fullScreenAssignments(
                                accountIDs: accountIDs,
                                displays: controller.displays
                            )
                        )
                    }
                    .disabled(controller.displays.isEmpty)
                    .help("Give each selected profile its own macOS full-screen Space")
                }

                if !canArrangeAutomatically, !controller.displays.isEmpty {
                    Text("Automatic arrangement fits up to four profiles on each display. Use Full Screen All, or place the extra profiles yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if accounts.isEmpty {
                Text("Select at least one profile to arrange its Roblox window.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    profileShelf
                        .frame(width: 210, height: 365)

                    VStack(spacing: 12) {
                        if controller.displays.isEmpty {
                            noDisplays
                        } else {
                            ForEach(controller.displays) { display in
                                MonitorLayoutCard(
                                    display: display,
                                    accounts: accounts,
                                    assignments: assignmentDictionary,
                                    selectedAccountID: $selectedAccountID,
                                    compact: true,
                                    onAssign: assign
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(WindowControlSpacing.contentInset)
        .disabled(disabled)
        .onAppear {
            controller.refreshDisplays()
        }
        .onChange(of: accountIDs) { _ in
            clearUnavailableSelection()
        }
    }

    private var statusText: String {
        usesSavedPlacements
            ? "Using the saved arrangement. Move a profile to customize this launch."
            : customStatus
    }

    private var profileShelf: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profiles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(placementCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(WindowControlSpacing.contentInset)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(accounts) { account in
                        Button {
                            selectedAccountID = account.id
                        } label: {
                            WindowLayoutAccountRow(
                                account: account,
                                assignment: assignmentDictionary[account.id]
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                if selectedAccountID == account.id {
                                    RoundedRectangle(
                                        cornerRadius: AppGeometry.controlCornerRadius,
                                        style: .continuous
                                    )
                                    .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.18))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedAccountID == account.id ? .isSelected : [])
                        .draggable(account.id.uuidString) {
                            WindowLayoutDragPreview(account: account)
                        }
                        .contextMenu {
                            placementMenus(for: account)
                            if assignmentDictionary[account.id] != nil {
                                Divider()
                                Button("Remove Placement") { remove(account.id) }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
        }
        .background(.bar)
        .appRoundedPanel()
    }

    private var noDisplays: some View {
        VStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No Displays Found")
                .fontWeight(.medium)
            Text("Reconnect a display, then reopen this view.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 390)
        .background(Color(nsColor: .controlBackgroundColor))
        .appRoundedPanel()
    }

    private var accountIDs: [UUID] {
        accounts.map(\.id)
    }

    private var assignmentDictionary: [UUID: WindowLayoutAssignment] {
        Dictionary(
            assignments.map { ($0.accountID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
    }

    private var placementCountText: String {
        "\(assignments.count) of \(accounts.count) placed"
    }

    private var canArrangeAutomatically: Bool {
        !controller.displays.isEmpty
            && accounts.count <= controller.displays.count * WindowArrangementPlanner.maximumWindowedProfilesPerDisplay
    }

    private var automaticArrangementHelp: String {
        canArrangeAutomatically
            ? "Fit up to four Roblox windows on each connected display"
            : "Automatic arrangement needs one display for every four selected profiles"
    }

    private func clearUnavailableSelection() {
        guard let selectedAccountID, !accountIDs.contains(selectedAccountID) else { return }
        self.selectedAccountID = nil
    }

    private func assign(
        _ accountID: UUID,
        _ display: ConnectedDisplay,
        _ region: WindowPlacementRegion
    ) {
        guard controller.ensureAccessibilityPermission() else { return }
        var updated = assignmentDictionary.filter { existingAccountID, assignment in
            if existingAccountID == accountID { return false }
            guard assignment.displayID == display.id else { return true }
            return !WindowPlacementGeometry.regionsOverlap(assignment.region, region)
        }
        updated[accountID] = WindowLayoutAssignment(
            accountID: accountID,
            displayID: display.id,
            displayName: display.name,
            displayPixelWidth: display.pixelWidth,
            displayPixelHeight: display.pixelHeight,
            region: region
        )
        publish(updated)
    }

    private func remove(_ accountID: UUID) {
        var updated = assignmentDictionary
        updated[accountID] = nil
        publish(updated)
    }

    private func publish(_ updated: [UUID: WindowLayoutAssignment]) {
        onAssignmentsChange(updated.values.sorted { $0.accountID.uuidString < $1.accountID.uuidString })
    }

    @ViewBuilder
    private func placementMenus(for account: ManagedAccount) -> some View {
        ForEach(controller.displays) { display in
            Menu(display.name) {
                ForEach(WindowPlacementRegion.windowedCases) { region in
                    Button(region.title) { assign(account.id, display, region) }
                }
                Divider()
                Button(WindowPlacementRegion.fullScreen.title) {
                    assign(account.id, display, .fullScreen)
                }
            }
        }
    }
}

struct WindowLayoutView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var controller: WindowLayoutController
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedAccountID: UUID?

    var body: some View {
        NavigationSplitView {
            accountShelf
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
        } detail: {
            monitorWorkspace
        }
        .navigationTitle("Launch Defaults")
        .onAppear {
            controller.refreshDisplays()
            selectedAccountID = selectedAccountID ?? store.accounts.first?.id
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { controller.refreshDisplays() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            controller.refreshDisplays()
        }
    }

    private var accountShelf: some View {
        VStack(spacing: 0) {
            List(selection: $selectedAccountID) {
                Section {
                    ForEach(store.accounts) { account in
                        WindowLayoutAccountRow(
                            account: account,
                            assignment: controller.assignment(for: account.id)
                        )
                        .tag(account.id)
                        .draggable(account.id.uuidString) {
                            WindowLayoutDragPreview(account: account)
                        }
                        .contextMenu {
                            placementMenus(for: account)
                            if controller.assignment(for: account.id) != nil {
                                Divider()
                                Button("Remove Placement") { controller.clear(accountID: account.id) }
                            }
                        }
                        .zIndex(2)
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Choose a profile, then choose a windowed area or Full-screen Spaces. A larger windowed area replaces profiles in any area it overlaps.")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if !controller.assignments.isEmpty {
                HStack {
                    Text("\(controller.assignments.count) placed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") { controller.clearAll() }
                }
                .font(.caption)
                .padding(AppGeometry.windowEdgeControlInset)
            }
        }
        .background(.bar)
    }

    private var monitorWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                launchSettingsDefaults

                permissionStatus

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick layouts")
                        .font(.headline)
                    Text("Start with a complete layout, then move individual profiles only when you need to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Arrange Automatically") {
                            guard controller.ensureAccessibilityPermission() else { return }
                            controller.arrangeAutomatically(accountIDs: store.accounts.map(\.id))
                        }
                        .disabled(!canArrangeAutomatically)
                        .help(automaticArrangementHelp)

                        Button("Full Screen All") {
                            guard controller.ensureAccessibilityPermission() else { return }
                            controller.makeFullScreen(accountIDs: store.accounts.map(\.id))
                        }
                        .disabled(controller.displays.isEmpty || store.accounts.isEmpty)
                        .help("Give each profile its own macOS full-screen Space")
                    }

                    if !store.accounts.isEmpty,
                       !controller.displays.isEmpty,
                       !canArrangeAutomatically {
                        Text("Automatic arrangement fits up to four profiles on each display. Use Full Screen All, or place the extra profiles yourself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WindowControlSpacing.contentInset)
                .background(Color(nsColor: .controlBackgroundColor))
                .appRoundedPanel()

                if let message = controller.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(WindowControlSpacing.contentInset)
                }

                if controller.displays.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "display")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No Displays Found")
                            .font(.title3.weight(.semibold))
                        Text("Reconnect a display or reopen this window.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    ForEach(controller.displays) { display in
                        MonitorLayoutCard(
                            display: display,
                            accounts: store.accounts,
                            assignments: controller.assignments,
                            selectedAccountID: $selectedAccountID,
                            compact: false,
                            onAssign: { accountID, display, region in
                                guard controller.ensureAccessibilityPermission() else { return }
                                controller.assign(accountID: accountID, to: display, region: region)
                            }
                        )
                    }
                }

                Text("Windowed layouts use the area left by the menu bar, Dock, and camera housing. Fill Desktop stays in the current desktop. Full Screen creates one macOS Space for each profile. Roblox stays unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(WindowControlSpacing.contentInset)
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(AppGeometry.windowContentInset)
        }
    }

    private var canArrangeAutomatically: Bool {
        !store.accounts.isEmpty
            && !controller.displays.isEmpty
            && store.accounts.count <= controller.displays.count * WindowArrangementPlanner.maximumWindowedProfilesPerDisplay
    }

    private var automaticArrangementHelp: String {
        canArrangeAutomatically
            ? "Fit up to four Roblox windows on each connected display"
            : "Automatic arrangement needs one display for every four profiles"
    }

    private var launchSettingsDefaults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Graphics and sound")
                .font(.headline)
            Text("These settings apply before every Roblox launch. Leave Unchanged keeps the value already saved in Roblox.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LaunchSettingsControls(settings: $store.launchSettings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WindowControlSpacing.contentInset)
        .background(Color(nsColor: .controlBackgroundColor))
        .appRoundedPanel()
    }

    @ViewBuilder
    private var permissionStatus: some View {
        if controller.accessibilityPermissionGranted {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window control is ready")
                        .fontWeight(.medium)
                    Text("The saved arrangement will apply after each Roblox launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(WindowControlSpacing.contentInset)
            .background(Color(nsColor: .controlBackgroundColor))
            .appRoundedPanel()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.slash")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow window control")
                        .fontWeight(.medium)
                    Text("Turn on Roblox Account Manager. If it is already on, turn it off and on again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Open Accessibility Settings") {
                        controller.requestAccessibilityPermission()
                    }
                    Button("Check Again") {
                        controller.refreshAccessibilityPermission()
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(WindowControlSpacing.contentInset)
            .background(Color(nsColor: .controlBackgroundColor))
            .appRoundedPanel()
        }
    }

    @ViewBuilder
    private func placementMenus(for account: ManagedAccount) -> some View {
        ForEach(controller.displays) { display in
            Menu(display.name) {
                ForEach(WindowPlacementRegion.windowedCases) { region in
                    Button(region.title) {
                        guard controller.ensureAccessibilityPermission() else { return }
                        controller.assign(accountID: account.id, to: display, region: region)
                    }
                }
                Divider()
                Button(WindowPlacementRegion.fullScreen.title) {
                    guard controller.ensureAccessibilityPermission() else { return }
                    controller.assign(accountID: account.id, to: display, region: .fullScreen)
                }
            }
        }
    }
}

private struct WindowLayoutAccountRow: View {
    let account: ManagedAccount
    let assignment: WindowLayoutAssignment?

    var body: some View {
        HStack(spacing: 9) {
            AccountAvatarView(
                url: account.avatarURL,
                size: 34,
                cornerRadius: AppGeometry.smallThumbnailRadius
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(account.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(assignmentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private var assignmentDescription: String {
        guard let assignment else { return "Not placed" }
        return "\(assignment.displayName) · \(assignment.region.title)"
    }
}

private struct WindowLayoutDragPreview: View {
    let account: ManagedAccount

    var body: some View {
        HStack(spacing: 8) {
            AccountAvatarView(
                url: account.avatarURL,
                size: 28,
                cornerRadius: AppGeometry.smallThumbnailRadius
            )
            Text(account.title)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous))
    }
}

private struct MonitorLayoutCard: View {
    let display: ConnectedDisplay
    let accounts: [ManagedAccount]
    let assignments: [UUID: WindowLayoutAssignment]
    @Binding var selectedAccountID: UUID?
    let compact: Bool
    let onAssign: (UUID, ConnectedDisplay, WindowPlacementRegion) -> Void
    @State private var targetedRegion: WindowPlacementRegion?
    @State private var fullScreenTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(.headline)
                    Text("\(display.pixelWidth) × \(display.pixelHeight) pixels · \(display.usablePixelWidth) × \(display.usablePixelHeight) usable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(placedCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let size = fittedPreviewSize(in: geometry.size)
                ZStack {
                    RoundedRectangle(cornerRadius: AppGeometry.panelCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))

                    GeometryReader { canvasGeometry in
                        VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { column in
                                        if let region = region(row: row, column: column) {
                                            MonitorDropTarget(
                                                region: region,
                                                selectedAccountID: selectedAccountID,
                                                showsLabel: selectedAccountID != nil,
                                                isTargeted: targetedRegion == region,
                                                onTargetChange: { targeted in
                                                    targetedRegion = targeted ? region : nil
                                                },
                                                onDrop: { accountID in
                                                    selectedAccountID = accountID
                                                    onAssign(accountID, display, region)
                                                    selectedAccountID = nil
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .zIndex(selectedAccountID == nil ? 0 : 2)

                        ForEach(placedProfiles) { placement in
                            let frame = previewFrame(for: placement.region, in: canvasGeometry.size)
                            Group {
                                if selectedAccountID == nil {
                                    PlacedProfileWindow(
                                        account: placement.account,
                                        region: placement.region
                                    )
                                } else {
                                    PlacementFootprint()
                                }
                            }
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                            .zIndex(1)
                        }

                        if let targetedRegion {
                            let frame = previewFrame(for: targetedRegion, in: canvasGeometry.size)
                            RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .allowsHitTesting(false)
                                .zIndex(3)
                        }
                    }
                    .padding(AppGeometry.panelEdgeControlInset)
                }
                .frame(width: size.width, height: size.height)
                .appRoundedPanel(radius: AppGeometry.panelCornerRadius)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(height: compact ? 210 : 220)

            fullScreenTarget
        }
        .padding(WindowControlSpacing.contentInset)
        .background(Color(nsColor: .controlBackgroundColor))
        .appRoundedPanel()
    }

    private var placedCountText: String {
        let windowedCount = placedProfiles.count
        let fullScreenCount = fullScreenProfiles.count
        if fullScreenCount == 0 {
            return windowedCount == 1 ? "1 windowed" : "\(windowedCount) windowed"
        }
        return "\(windowedCount) windowed · \(fullScreenCount) full screen"
    }

    private var placedProfiles: [PlacedProfile] {
        assignments.values.compactMap { assignment in
            guard assignment.displayID == display.id,
                  !assignment.region.isNativeFullScreen,
                  let account = accounts.first(where: { $0.id == assignment.accountID }) else { return nil }
            return PlacedProfile(account: account, region: assignment.region)
        }
    }

    private var fullScreenProfiles: [ManagedAccount] {
        assignments.values.compactMap { assignment in
            guard assignment.displayID == display.id,
                  assignment.region.isNativeFullScreen else { return nil }
            return accounts.first(where: { $0.id == assignment.accountID })
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @ViewBuilder
    private var fullScreenTarget: some View {
        Group {
            if let selectedAccountID {
                Button {
                    onAssign(selectedAccountID, display, .fullScreen)
                    self.selectedAccountID = nil
                } label: {
                    fullScreenTargetLabel
                }
                .buttonStyle(.plain)
                .accessibilityHint("Put the selected profile in its own full-screen Space")
            } else {
                fullScreenTargetLabel
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let accountID = UUID(uuidString: value) else { return false }
            onAssign(accountID, display, .fullScreen)
            selectedAccountID = nil
            return true
        } isTargeted: { targeted in
            fullScreenTargeted = targeted
        }
        .help("Each profile opens in its own native macOS full-screen Space")
    }

    private var fullScreenTargetLabel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Full-screen Spaces")
                    .font(.subheadline.weight(.semibold))
                Text("Each profile gets its own macOS Space on this display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if fullScreenProfiles.isEmpty {
                Text(fullScreenTargetIsActive ? "Place here" : "No profiles")
                    .font(.caption)
                    .foregroundStyle(fullScreenTargetIsActive ? Color.accentColor : Color.secondary)
            } else {
                HStack(spacing: 7) {
                    ForEach(fullScreenProfiles.prefix(4)) { account in
                        AccountAvatarView(
                            url: account.avatarURL,
                            size: 26,
                            cornerRadius: AppGeometry.smallThumbnailRadius
                        )
                        .help(account.title)
                    }
                    if fullScreenProfiles.count > 4 {
                        Text("+\(fullScreenProfiles.count - 4)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(WindowControlSpacing.contentInset)
        .background {
            RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                .fill(selectedAccountID == nil
                    && !fullScreenTargeted
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color.accentColor.opacity(0.08))
        }
        .overlay {
            if fullScreenTargetIsActive {
                RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Full-screen Spaces on \(display.name), \(fullScreenProfiles.count) profiles")
    }

    private var fullScreenTargetIsActive: Bool {
        selectedAccountID != nil || fullScreenTargeted
    }

    private func region(row: Int, column: Int) -> WindowPlacementRegion? {
        WindowPlacementRegion.windowedCases.first { $0.gridRow == row && $0.gridColumn == column }
    }

    private func fittedPreviewSize(in available: CGSize) -> CGSize {
        let aspect = max(1, display.visibleFrame.width) / max(1, display.visibleFrame.height)
        let maximumWidth = max(1, available.width)
        let maximumHeight = max(1, available.height)
        let widthFromHeight = maximumHeight * aspect
        if widthFromHeight <= maximumWidth {
            return CGSize(width: widthFromHeight, height: maximumHeight)
        }
        return CGSize(width: maximumWidth, height: maximumWidth / aspect)
    }

    private func previewFrame(for region: WindowPlacementRegion, in size: CGSize) -> CGRect {
        let normalized = WindowPlacementGeometry.frame(
            in: CGRect(x: 0, y: 0, width: 1, height: 1),
            region: region
        )
        let gap: CGFloat = 2
        return CGRect(
            x: normalized.minX * size.width + gap,
            y: (1 - normalized.maxY) * size.height + gap,
            width: max(1, normalized.width * size.width - gap * 2),
            height: max(1, normalized.height * size.height - gap * 2)
        )
    }
}

private struct PlacementFootprint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
            .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .selectedContentBackgroundColor).opacity(0.25), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct PlacedProfile: Identifiable {
    let account: ManagedAccount
    let region: WindowPlacementRegion
    var id: UUID { account.id }
}

private struct PlacedProfileWindow: View {
    let account: ManagedAccount
    let region: WindowPlacementRegion

    var body: some View {
        VStack(spacing: 5) {
            AccountAvatarView(
                url: account.avatarURL,
                size: 30,
                cornerRadius: AppGeometry.smallThumbnailRadius
            )
            Text(account.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(region.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Color(nsColor: .selectedContentBackgroundColor).opacity(0.16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppGeometry.controlCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .selectedContentBackgroundColor).opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.title), \(region.title)")
    }
}

private struct MonitorDropTarget: View {
    let region: WindowPlacementRegion
    let selectedAccountID: UUID?
    let showsLabel: Bool
    let isTargeted: Bool
    let onTargetChange: (Bool) -> Void
    let onDrop: (UUID) -> Void

    var body: some View {
        Group {
            if let selectedAccountID {
                Button {
                    onDrop(selectedAccountID)
                } label: {
                    targetLabel
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(region.title)
                .accessibilityHint("Place the selected profile here")
            } else {
                targetLabel
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let accountID = UUID(uuidString: value) else { return false }
            onDrop(accountID)
            return true
        } isTargeted: { targeted in
            onTargetChange(targeted)
        }
        .help("Place the selected or dragged profile at \(region.title.lowercased())")
    }

    private var targetLabel: some View {
        Text(region.shortTitle)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            .opacity(showsLabel || isTargeted ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
    }
}

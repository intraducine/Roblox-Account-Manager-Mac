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

struct AdvancedLaunchOptions: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    let onRequestModifiedFallback: () -> Void

    var body: some View {
        FullWidthDisclosure("Advanced options") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Place ID")
                    Spacer(minLength: 24)
                    TextField("Place ID", text: $placeID)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                }
                Text("Choose Game fills this number automatically. Most people do not need to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if store.launchMode != .modifiedParallel {
                    LaunchClientNotice(
                        store: store,
                        onRequestModifiedFallback: onRequestModifiedFallback
                    )
                }
            }
        }
    }
}

struct FullWidthDisclosure<Content: View>: View {
    let title: String
    @State private var isExpanded = false
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 10)
                    Text(title)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content()
                    .padding(.top, 12)
            }
        }
    }
}

struct LaunchClientNotice: View {
    @ObservedObject var store: AccountStore
    let onRequestModifiedFallback: () -> Void
    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isModified ? "Modified-copy fallback is active" : "Unchanged Roblox copies")
                    .fontWeight(.semibold)
                    .foregroundStyle(isModified ? Color.orange : .primary)
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

            Button("How Multiple Apps Work") { showsDetails = true }
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
            return "The manager changed each copied app so macOS can start it separately. Roblox may treat it as a modified client."
        }
        return "Recommended. Each account opens in its own copy, but every Roblox file and the Roblox signature stay unchanged."
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How This App Opens Several Roblox Accounts")
                .font(.headline)

            Text("The manager makes a separate app copy for each saved account. This lets a second Roblox account open without closing the first one.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unchanged copies (recommended)")
                    .fontWeight(.semibold)
                Text("The manager copies the Roblox app already installed on your Mac. It does not edit any file inside the copy. The copy keeps Roblox Corporation's original signature, and the manager checks it before every launch.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Modified copies (advanced fallback)")
                    .fontWeight(.semibold)
                Text("Use this only if unchanged copies stop working. This method changes the copied app and gives it a new signature. Roblox can detect that change and may restrict an account that uses it.")
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
        .padding(AppGeometry.windowContentInset)
    }
}

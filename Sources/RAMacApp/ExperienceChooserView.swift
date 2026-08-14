import AppKit
import RAMacCore
import SwiftUI

struct ExperienceChooserButton: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    var knownName: String?
    var onChoose: ((ExperienceRecord) -> Void)?
    @State private var showsChooser = false
    @State private var selectedExperience: ExperienceRecord?

    init(
        store: AccountStore,
        placeID: Binding<String>,
        knownName: String? = nil,
        onChoose: ((ExperienceRecord) -> Void)? = nil
    ) {
        self.store = store
        _placeID = placeID
        self.knownName = knownName
        self.onChoose = onChoose
    }

    var body: some View {
        Button { showsChooser = true } label: {
            if let experience = displayedExperience {
                HStack(spacing: 8) {
                    ExperienceIcon(experience: experience, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(experience.experienceName ?? "Selected Game")
                            .lineLimit(1)
                        Text("Change game")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Choose Game", systemImage: "gamecontroller")
            }
        }
        .sheet(isPresented: $showsChooser) {
            ExperienceChooserView(store: store) { experience in
                selectedExperience = experience
                placeID = String(experience.placeID)
                onChoose?(experience)
                showsChooser = false
            }
        }
        .onChange(of: placeID) { newValue in
            guard selectedExperience?.placeID != Int64(newValue) else { return }
            selectedExperience = nil
        }
        .task(id: placeID) {
            guard let numericID = Int64(placeID), numericID > 0,
                  selectedExperience?.placeID != numericID else { return }
            if let experience = try? await store.findExperience(placeID: numericID) {
                selectedExperience = experience
            }
        }
    }

    private var displayedExperience: ExperienceRecord? {
        if let selectedExperience { return selectedExperience }
        guard let numericID = Int64(placeID) else { return nil }
        return store.experiences.first(where: { $0.placeID == numericID })
            ?? knownName.map { ExperienceRecord(placeID: numericID, experienceName: $0) }
    }
}

private struct ExperienceChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    let onChoose: (ExperienceRecord) -> Void
    @State private var search = ""
    @State private var gameReference = ""
    @State private var foundExperience: ExperienceRecord?
    @State private var lookupMessage: String?
    @State private var isFinding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Find a Game") {
                    Text("Paste the Roblox game link. The app will show the game before you choose it.")
                        .foregroundStyle(.secondary)
                    TextField("Roblox game link or Place ID", text: $gameReference)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit { findGame() }

                    HStack {
                        Spacer()
                        Button(isFinding ? "Finding" : "Find Game") { findGame() }
                            .disabled(isFinding || RobloxGameReference.placeID(from: gameReference) == nil)
                    }
                    if isFinding {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Finding this game on Roblox")
                                .foregroundStyle(.secondary)
                        }
                    } else if let foundExperience {
                        experienceRow(foundExperience, showFavoriteButton: false)
                    } else if let lookupMessage {
                        Text(lookupMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Recent and Favorite Games") {
                    if filteredExperiences.isEmpty {
                        Text(search.isEmpty
                            ? "Games will appear here after you launch them."
                            : "No saved games match this search.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredExperiences) { experience in
                            experienceRow(experience, showFavoriteButton: true)
                        }
                    }
                }
            }
            .task { await store.refreshExperienceMetadata() }
            .searchable(text: $search, prompt: "Search recent games")
            .navigationTitle("Choose a Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 660, height: 540)
    }

    private func findGame() {
        guard let placeID = RobloxGameReference.placeID(from: gameReference) else {
            foundExperience = nil
            lookupMessage = "Paste a Roblox link that contains /games/, or enter its Place ID."
            return
        }
        foundExperience = nil
        lookupMessage = nil
        isFinding = true
        Task {
            do {
                foundExperience = try await store.findExperience(placeID: placeID)
            } catch {
                lookupMessage = "Roblox could not find that game. Check the link and try again."
            }
            isFinding = false
        }
    }

    private func experienceRow(
        _ experience: ExperienceRecord,
        showFavoriteButton: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ExperienceIcon(
                experience: experience,
                size: 52,
                showsProgress: store.experienceMetadataLoadingIDs.contains(experience.placeID)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(experience.experienceName ?? "Roblox Game").fontWeight(.medium)
                Text("Place ID \(experience.placeID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showFavoriteButton {
                Button(
                    experience.isFavorite ? "Remove Favorite" : "Add Favorite",
                    systemImage: experience.isFavorite ? "star.fill" : "star"
                ) {
                    store.setExperienceFavorite(experience, isFavorite: !experience.isFavorite)
                }
                .labelStyle(.iconOnly)
            }
            Button("Choose") { onChoose(experience) }
        }
        .padding(.vertical, 3)
    }

    private var filteredExperiences: [ExperienceRecord] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.experiences.filter {
            needle.isEmpty
                || String($0.placeID).contains(needle)
                || ($0.experienceName?.localizedCaseInsensitiveContains(needle) ?? false)
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.lastLaunchedAt > $1.lastLaunchedAt
        }
    }
}

private struct ExperienceIcon: View {
    let experience: ExperienceRecord
    let size: CGFloat
    var showsProgress = false
    @State private var image: NSImage?
    @State private var loadedURL: URL?

    init(experience: ExperienceRecord, size: CGFloat, showsProgress: Bool = false) {
        self.experience = experience
        self.size = size
        self.showsProgress = showsProgress
        let cachedImage = RemoteImageCache.image(for: experience.thumbnailURL)
        _image = State(initialValue: cachedImage)
        _loadedURL = State(initialValue: cachedImage == nil ? nil : experience.thumbnailURL)
    }

    var body: some View {
        Group {
            if let displayedImage {
                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFill()
            } else if showsProgress {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppGeometry.thumbnailRadius(for: size),
                style: .continuous
            )
        )
        .task(id: experience.thumbnailURL) {
            let url = experience.thumbnailURL
            image = RemoteImageCache.image(for: url)
            loadedURL = image == nil ? nil : url
            guard image == nil, let url else { return }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loadedImage = NSImage(data: data) else { return }
            RemoteImageCache.insert(loadedImage, for: url)
            guard experience.thumbnailURL == url else { return }
            image = loadedImage
            loadedURL = url
        }
        .accessibilityHidden(true)
    }

    private var displayedImage: NSImage? {
        let url = experience.thumbnailURL
        if loadedURL == url {
            return image
        }
        return RemoteImageCache.image(for: url)
    }
}

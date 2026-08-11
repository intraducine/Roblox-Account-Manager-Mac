import RAMacCore
import SwiftUI

struct ExperienceChooserButton: View {
    @ObservedObject var store: AccountStore
    @Binding var placeID: String
    @State private var showsChooser = false

    var body: some View {
        Button("Choose Game") { showsChooser = true }
            .sheet(isPresented: $showsChooser) {
                ExperienceChooserView(store: store) { experience in
                    placeID = String(experience.placeID)
                    showsChooser = false
                }
            }
    }
}

private struct ExperienceChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    let onChoose: (ExperienceRecord) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if filteredExperiences.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(search.isEmpty ? "No recent experiences yet." : "No experiences match this search.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredExperiences) { experience in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(experience.experienceName ?? "Place \(experience.placeID)").fontWeight(.medium)
                                Text("Place ID \(experience.placeID) · launched \(experience.launchCount) time\(experience.launchCount == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(experience.isFavorite ? "Remove Favorite" : "Add Favorite", systemImage: experience.isFavorite ? "star.fill" : "star") {
                                store.setExperienceFavorite(experience, isFavorite: !experience.isFavorite)
                            }
                            .labelStyle(.iconOnly)
                            Button("Choose") { onChoose(experience) }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search games or Place IDs")
            .navigationTitle("Recent and Favorite Games")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 620, height: 500)
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

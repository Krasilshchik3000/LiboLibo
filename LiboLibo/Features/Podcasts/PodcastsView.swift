import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PodcastColorService.self) private var colors

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section("Выходят сейчас") {
                        ForEach(active) { podcast in
                            NavigationLink(value: podcast) { PodcastRow(podcast: podcast) }
                        }
                    }
                }
                if !recent.isEmpty {
                    Section("Недавно выходили") {
                        ForEach(recent) { podcast in
                            NavigationLink(value: podcast) { PodcastRow(podcast: podcast) }
                        }
                    }
                }
                if !dormant.isEmpty {
                    Section("Давно не выходят") {
                        ForEach(dormant) { podcast in
                            NavigationLink(value: podcast) { PodcastRow(podcast: podcast) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Подкасты")
            .navigationDestination(for: Podcast.self) { podcast in
                PodcastDetailView(podcast: podcast)
            }
        }
        .task(id: repository.podcasts.count) {
            for podcast in repository.podcasts {
                colors.ensureTint(for: podcast.id, artworkUrl: podcast.artworkUrl)
            }
        }
    }

    // MARK: - Segmentation

    /// Иноязычные версии шоу (Harbin DE, The Adults in the Room EN, The Naked
    /// Mole Rat EN) скрыты с этого экрана: у них и название, и описание не
    /// содержат кириллицы. Если такой подкаст обогатится русским описанием
    /// в RSS — он автоматически вернётся в список.
    private var russianPodcasts: [Podcast] {
        repository.podcasts.filter { $0.name.containsCyrillic || ($0.description?.containsCyrillic ?? false) }
    }

    private var active: [Podcast] {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        return russianPodcasts
            .filter { ($0.lastEpisodeDate ?? .distantPast) >= cutoff }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var recent: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        let threeAgo = Date().addingTimeInterval(-90 * 86400)
        return russianPodcasts
            .filter {
                guard let d = $0.lastEpisodeDate else { return false }
                return d < threeAgo && d >= twelveAgo
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var dormant: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        return russianPodcasts
            .filter { (p: Podcast) -> Bool in
                guard let d = p.lastEpisodeDate else { return true }
                return d < twelveAgo
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private extension String {
    var containsCyrillic: Bool {
        contains { $0.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
    }
}

/// Та же типографика, что и в `EpisodeRow` (Фид):
/// .caption — артист, .headline — название, .subheadline — превью описания.
private struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: podcast.artworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(podcast.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let desc = podcast.description {
                    let preview = desc.firstSentences(maxCount: 2)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    PodcastsView()
        .environment(PodcastsRepository())
}

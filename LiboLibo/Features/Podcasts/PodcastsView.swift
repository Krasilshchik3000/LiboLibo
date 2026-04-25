import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastsRepository.self) private var repository

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
    }

    // MARK: - Segmentation

    private var active: [Podcast] {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        return repository.podcasts
            .filter { ($0.lastEpisodeDate ?? .distantPast) >= cutoff }
            .sorted { ($0.lastEpisodeDate ?? .distantPast) > ($1.lastEpisodeDate ?? .distantPast) }
    }

    private var recent: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        let threeAgo = Date().addingTimeInterval(-90 * 86400)
        return repository.podcasts
            .filter {
                guard let d = $0.lastEpisodeDate else { return false }
                return d < threeAgo && d >= twelveAgo
            }
            .sorted { ($0.lastEpisodeDate ?? .distantPast) > ($1.lastEpisodeDate ?? .distantPast) }
    }

    private var dormant: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        return repository.podcasts
            .filter { (p: Podcast) -> Bool in
                guard let d = p.lastEpisodeDate else { return true }
                return d < twelveAgo
            }
            .sorted { ($0.lastEpisodeDate ?? .distantPast) > ($1.lastEpisodeDate ?? .distantPast) }
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

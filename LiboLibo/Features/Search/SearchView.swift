import SwiftUI

/// Объектный поиск: один запрос, результаты сгруппированы по типу — «Подкасты» и «Выпуски».
struct SearchView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PlayerService.self) private var player

    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Поиск")
                .navigationDestination(for: Podcast.self) { podcast in
                    PodcastDetailView(podcast: podcast)
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Найти подкаст или выпуск"
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    // MARK: - Filtering

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingPodcasts: [Podcast] {
        let q = trimmedQuery.localizedLowercase
        guard !q.isEmpty else { return [] }
        return repository.podcasts.filter { $0.name.localizedLowercase.contains(q) }
    }

    private var matchingEpisodes: [Episode] {
        let q = trimmedQuery.localizedLowercase
        guard !q.isEmpty else { return [] }
        return Array(repository.allEpisodes.lazy
            .filter {
                $0.title.localizedLowercase.contains(q)
                    || $0.summary.localizedLowercase.contains(q)
            }
            .prefix(50))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            ContentUnavailableView(
                "Поиск",
                systemImage: "magnifyingglass",
                description: Text("Введи слово, чтобы найти подкаст или выпуск.")
            )
        } else if matchingPodcasts.isEmpty && matchingEpisodes.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            List {
                if !matchingPodcasts.isEmpty {
                    Section("Подкасты") {
                        ForEach(matchingPodcasts) { podcast in
                            NavigationLink(value: podcast) {
                                PodcastSearchRow(podcast: podcast)
                            }
                        }
                    }
                }

                if !matchingEpisodes.isEmpty {
                    Section("Выпуски") {
                        ForEach(matchingEpisodes) { episode in
                            Button {
                                player.play(episode)
                            } label: {
                                EpisodeRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct PodcastSearchRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: podcast.artworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(podcast.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

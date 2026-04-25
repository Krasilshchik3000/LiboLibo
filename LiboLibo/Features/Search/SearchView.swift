import SwiftUI

struct SearchView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PlayerService.self) private var player

    @State private var query = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Поиск")
                .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0, path: $path) }
                .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Найти подкаст или выпуск"
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .task {
                    if repository.allEpisodes.isEmpty {
                        await repository.loadAllEpisodes()
                    }
                }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingPodcasts: [Podcast] {
        let q = trimmedQuery.localizedLowercase
        guard !q.isEmpty else { return [] }
        return repository.podcasts.filter {
            $0.name.localizedLowercase.contains(q)
                || $0.artist.localizedLowercase.contains(q)
        }
    }

    private var matchingEpisodes: [Episode] {
        let q = trimmedQuery.localizedLowercase
        guard !q.isEmpty else { return [] }
        return Array(repository.allEpisodes.lazy
            .filter {
                $0.title.localizedLowercase.contains(q)
                    || $0.summary.localizedLowercase.contains(q)
                    || $0.podcastName.localizedLowercase.contains(q)
            }
            .prefix(50))
    }

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
                            EpisodeListItem(
                                episode: episode,
                                onPlay: { player.play(episode) },
                                onShowDetail: { path.append(episode) },
                                onPlayNext: { player.playNext(episode) },
                                onNavigateToPodcast: {
                                    if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                                        path.append(podcast)
                                    }
                                }
                            )
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
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(podcast.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

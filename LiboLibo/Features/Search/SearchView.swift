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
                                PodcastRow(podcast: podcast, density: .compact)
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
                                onShowDetail: { path.append(episode) }
                            )
                        }
                    }
                }
            }
        }
    }
}


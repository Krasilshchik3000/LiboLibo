import SwiftUI

struct ProfileView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(SubscriptionsService.self) private var subscriptions
    @Environment(HistoryService.self) private var history
    @Environment(DownloadService.self) private var downloads
    @Environment(PlayerService.self) private var player

    @State private var path = NavigationPath()
    @State private var showsClearHistoryAlert = false

    private var subscribedPodcasts: [Podcast] {
        repository.podcasts.filter { subscriptions.isSubscribed($0) }
    }

    private var recentFromSubscriptions: [Episode] {
        let ids = subscriptions.subscribedIds
        guard !ids.isEmpty else { return [] }
        return Array(
            repository.allEpisodes
                .filter { ids.contains($0.podcastId) }
                .prefix(20)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                subscriptionsSection
                if !downloads.items.isEmpty {
                    downloadedSection
                }
                if !recentFromSubscriptions.isEmpty {
                    recentSection
                }
                if !history.items.isEmpty {
                    historySection
                }
                if subscribedPodcasts.isEmpty
                    && history.items.isEmpty
                    && downloads.items.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Моё")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
            .alert("Очистить историю?", isPresented: $showsClearHistoryAlert) {
                Button("Очистить", role: .destructive) {
                    history.clearAll()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Список прослушанных выпусков будет удалён.")
            }
        }
    }

    private var subscriptionsSection: some View {
        Section("Подписки") {
            if subscribedPodcasts.isEmpty {
                Text("Открой «Подкасты» и подпишись на любой — он появится здесь.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(subscribedPodcasts) { podcast in
                    NavigationLink(value: podcast) {
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

                            Text(podcast.name)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var downloadedSection: some View {
        Section("Скачано") {
            ForEach(downloads.items) { item in
                let episode = item.asEpisode
                EpisodeListItem(
                    episode: episode,
                    onPlay: { player.play(episode) }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        downloads.deleteDownload(episode)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Свежее у подписок") {
            ForEach(recentFromSubscriptions) { episode in
                EpisodeListItem(
                    episode: episode,
                    onPlay: {
                        let context = repository.allEpisodes
                            .filter { $0.podcastId == episode.podcastId }
                            .sorted { $0.pubDate < $1.pubDate }
                        player.play(episode, context: context)
                    }
                )
            }
        }
    }

    private var historySection: some View {
        Section {
            ForEach(history.items) { item in
                let episode = history.episode(for: item)
                EpisodeListItem(
                    episode: episode,
                    onPlay: { player.play(episode) }
                )
            }
        } header: {
            HStack {
                Text("История")
                Spacer()
                Button {
                    showsClearHistoryAlert = true
                } label: {
                    Text("Очистить")
                        .font(.footnote)
                        .foregroundStyle(.liboRed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "Здесь будет твоя жизнь в подкастах",
                systemImage: "person.crop.circle",
                description: Text("Подписки, скачанные выпуски и история прослушиваний появятся, как только начнёшь слушать.")
            )
            .listRowBackground(Color.clear)
            .padding(.vertical, 24)
        }
    }
}

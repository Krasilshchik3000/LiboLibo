import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    /// Привязка к пути родительского NavigationStack — чтобы тап по «i» в
    /// строке выпуска пушил `EpisodeDetailView` в общую цепочку, а не в
    /// локальный «висящий» path (он бы ничего не делал, у этого view нет
    /// собственного NavigationStack).
    @Binding var path: NavigationPath

    @Environment(PlayerService.self) private var player
    @Environment(SubscriptionsService.self) private var subscriptions
    @Environment(DownloadService.self) private var downloads
    @Environment(PodcastColorService.self) private var colors

    @State private var episodes: [Episode] = []
    @State private var channelDescription: String?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        let tint = colors.tint(for: podcast.id)
        let accent = tint?.accent ?? .liboRed

        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        AsyncImage(url: podcast.artworkUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.secondary.opacity(0.15)
                            }
                        }
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(podcast.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                    }

                    Button {
                        subscriptions.toggle(podcast)
                    } label: {
                        Label(
                            subscriptions.isSubscribed(podcast) ? "Подписан" : "Подписаться",
                            systemImage: subscriptions.isSubscribed(podcast) ? "checkmark" : "plus"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(tint?.accentForeground ?? .white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(subscriptions.isSubscribed(podcast) ? .secondary : accent)

                    if let desc = channelDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if isLoading && episodes.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                } else if let loadError, episodes.isEmpty {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(episodes) { episode in
                        EpisodeListItem(
                            episode: episode,
                            onPlay: {
                                let context = episodes.sorted { $0.pubDate < $1.pubDate }
                                player.play(episode, context: context)
                            },
                            onShowDetail: { path.append(episode) },
                            showsPodcastName: false,
                            onPlayNext: { player.playNext(episode) }
                        )
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button { downloads.toggle(episode) } label: {
                                Label("Скачать", systemImage: "icloud.and.arrow.down")
                            }
                            .tint(accent)
                        }
                    }
                }
            } header: {
                Text("Выпуски")
            }
        }
        .scrollContentBackground(.hidden)
        .background { TintBackground(tint: tint) }
        .tint(.primary)
        .navigationTitle(podcast.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Episode.self) { episode in
            EpisodeDetailView(episode: episode)
        }
        .task(id: podcast.id) {
            colors.ensureTint(for: podcast.id, artworkUrl: podcast.artworkUrl)
            await load()
        }
    }

    private func load() async {
        // Описание подкаста теперь приходит из API (поле `Podcast.description`)
        // вместе с самим подкастом — отдельный поход в RSS больше не нужен.
        channelDescription = podcast.description

        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIClient.shared.fetchEpisodes(podcastId: podcast.id, limit: 200)
            episodes = fetched.episodes
            loadError = nil
        } catch {
            loadError = "Не удалось загрузить выпуски."
        }
    }
}

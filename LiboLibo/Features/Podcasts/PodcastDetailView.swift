import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast

    @Environment(PlayerService.self) private var player
    @Environment(SubscriptionsService.self) private var subscriptions
    @Environment(DownloadService.self) private var downloads

    @State private var episodes: [Episode] = []
    @State private var channelDescription: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var path = NavigationPath()

    var body: some View {
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
                            Text(podcast.artist)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(subscriptions.isSubscribed(podcast) ? .secondary : .liboRed)

                    if let desc = channelDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)

            Section("Выпуски") {
                if isLoading && episodes.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 12)
                } else if let loadError, episodes.isEmpty {
                    Text(loadError).foregroundStyle(.secondary)
                } else {
                    ForEach(episodes) { episode in
                        EpisodeListItem(
                            episode: episode,
                            onPlay: { player.play(episode) },
                            onShowDetail: { path.append(episode) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button { downloads.toggle(episode) } label: {
                                Label("Скачать", systemImage: "icloud.and.arrow.down")
                            }
                            .tint(.liboRed)
                        }
                    }
                }
            }
        }
        .navigationTitle(podcast.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Episode.self) { episode in
            EpisodeDetailView(episode: episode)
        }
        .task(id: podcast.id) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let feed = await PodcastsRepository.fetchFeed(for: podcast) {
            channelDescription = feed.channel.description
            episodes = feed.episodes.sorted { $0.pubDate > $1.pubDate }
            loadError = nil
        } else {
            loadError = "Не удалось загрузить выпуски."
        }
    }
}

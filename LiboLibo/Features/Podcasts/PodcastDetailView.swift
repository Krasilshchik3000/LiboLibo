import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast

    @Environment(PlayerService.self) private var player
    @Environment(SubscriptionsService.self) private var subscriptions

    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: podcast.artworkUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.secondary.opacity(0.15)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(podcast.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(podcast.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            subscriptions.toggle(podcast)
                        } label: {
                            Label(
                                subscriptions.isSubscribed(podcast) ? "Отписаться" : "Подписаться",
                                systemImage: subscriptions.isSubscribed(podcast) ? "bookmark.fill" : "bookmark"
                            )
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(subscriptions.isSubscribed(podcast) ? .secondary : .accentColor)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section("Выпуски") {
                if isLoading && episodes.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if let loadError, episodes.isEmpty {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(episodes) { episode in
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
        .navigationTitle(podcast.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: podcast.id) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched = await PodcastsRepository.fetchEpisodes(for: podcast)
        episodes = fetched.sorted { $0.pubDate > $1.pubDate }
        if fetched.isEmpty {
            loadError = "Не удалось загрузить выпуски."
        } else {
            loadError = nil
        }
    }
}

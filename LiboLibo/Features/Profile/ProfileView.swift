import SwiftUI

struct ProfileView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(SubscriptionsService.self) private var subscriptions
    @Environment(HistoryService.self) private var history
    @Environment(PlayerService.self) private var player

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
        NavigationStack {
            List {
                subscriptionsSection
                if !recentFromSubscriptions.isEmpty {
                    recentSection
                }
                if !history.items.isEmpty {
                    historySection
                }
                if subscribedPodcasts.isEmpty && history.items.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Моё")
            .navigationDestination(for: Podcast.self) { podcast in
                PodcastDetailView(podcast: podcast)
            }
        }
    }

    // MARK: - Sections

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
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Свежее у подписок") {
            ForEach(recentFromSubscriptions) { episode in
                Button {
                    player.play(episode)
                } label: {
                    EpisodeRow(episode: episode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historySection: some View {
        Section("История") {
            ForEach(history.items) { item in
                Button {
                    player.play(history.episode(for: item))
                } label: {
                    HistoryRow(item: item)
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
                description: Text("Подписки и история прослушиваний появятся, как только начнёшь слушать.")
            )
            .listRowBackground(Color.clear)
            .padding(.vertical, 24)
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryService.Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.podcastArtworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.podcastName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(item.lastPlayedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

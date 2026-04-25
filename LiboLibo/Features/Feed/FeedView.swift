import SwiftUI

struct FeedView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PlayerService.self) private var player

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Фид")
                .refreshable {
                    await repository.loadAllEpisodes()
                }
                .task {
                    if repository.allEpisodes.isEmpty {
                        await repository.loadAllEpisodes()
                    }
                }
                .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
                .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0, path: $path) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repository.isLoading && repository.allEpisodes.isEmpty {
            ProgressView("Загружаем выпуски…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if repository.allEpisodes.isEmpty {
            ContentUnavailableView(
                "Нет выпусков",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text(repository.loadError ?? "Потяните вниз, чтобы обновить.")
            )
        } else {
            List(repository.allEpisodes) { episode in
                EpisodeListItem(
                    episode: episode,
                    onPlay: {
                        let context = repository.allEpisodes.sorted { $0.pubDate < $1.pubDate }
                        player.play(episode, context: context)
                    },
                    onShowDetail: { path.append(episode) },
                    onPlayNext: { player.playNext(episode) },
                    onNavigateToPodcast: {
                        if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                            path.append(podcast)
                        }
                    }
                )
            }
            .listStyle(.plain)
        }
    }
}

struct EpisodeListItem: View {
    let episode: Episode
    let onPlay: () -> Void
    let onShowDetail: () -> Void
    var showsPodcastName: Bool = true
    var onPlayNext: (() -> Void)? = nil
    var onNavigateToPodcast: (() -> Void)? = nil

    @Environment(DownloadService.self) private var downloads

    var body: some View {
        Button(action: episode.isPlayable ? onPlay : onShowDetail) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: episode.podcastArtworkUrl) { phase in
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
                    if showsPodcastName {
                        Text(episode.podcastName)
                            .font(.caption)
                            .foregroundStyle(.liboRed)
                    }
                    Text(episode.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    let preview = episode.summary.firstSentences(maxCount: 2)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        if episode.isPlayable {
                            DownloadButton(episode: episode, style: .icon)
                                .frame(width: 28, height: 28, alignment: .leading)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28, alignment: .leading)
                                .accessibilityLabel("Доступно по подписке")
                        }
                        Text(metadataLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        episodeMenu
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var episodeMenu: some View {
        Menu {
            Button {
                downloads.toggle(episode)
            } label: {
                let downloaded = downloads.status(for: episode) == .downloaded
                Label(
                    downloaded ? "Удалить загрузку" : "Загрузить",
                    systemImage: downloaded ? "trash" : "icloud.and.arrow.down"
                )
            }

            ShareLink(
                item: "\(episode.podcastName) — \(episode.title)",
                subject: Text(episode.title),
                message: Text("Слушаю в Либо-Либо")
            ) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }

            if let onPlayNext {
                Button(action: onPlayNext) {
                    Label("Воспроизвести далее", systemImage: "text.insert")
                }
            }

            Button(action: onShowDetail) {
                Label("Перейти к выпуску", systemImage: "play.circle")
            }

            if let onNavigateToPodcast {
                Button(action: onNavigateToPodcast) {
                    Label("Перейти к подкасту", systemImage: "rectangle.grid.2x2")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var metadataLine: String {
        var parts: [String] = []
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let dur = episode.duration {
            let total = Int(dur.rounded())
            let h = total / 3600
            let m = (total % 3600) / 60
            parts.append(h > 0 ? "\(h) ч \(m) мин" : "\(m) мин")
        }
        return parts.joined(separator: " · ")
    }
}

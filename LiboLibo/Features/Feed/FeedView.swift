import SwiftUI

struct FeedView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloads

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
                .navigationDestination(for: Episode.self) { episode in
                    EpisodeDetailView(episode: episode)
                }
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
                EpisodeListItem(episode: episode) {
                    let context = repository.allEpisodes.sorted { $0.pubDate < $1.pubDate }
                    player.play(episode, context: context)
                } onShowDetail: {
                    path.append(episode)
                }
                .swipeActions(edge: .trailing) {
                    Button { downloads.toggle(episode) } label: {
                        switch downloads.status(for: episode) {
                        case .downloaded:    Label("Удалить", systemImage: "trash")
                        case .downloading:   Label("…", systemImage: "icloud")
                        case .notDownloaded: Label("Скачать", systemImage: "icloud.and.arrow.down")
                        }
                    }
                    .tint(.liboRed)
                }
            }
            .listStyle(.plain)
        }
    }
}

/// Элемент списка: тап по основной зоне — играет; тап по info-кнопке — открывает экран
/// выпуска. Apple Podcasts использует противоположный паттерн (row = детали, отдельная
/// кнопка ▶ = играть), но Илья выбрал «play — главная функция, детали — допфункция».
struct EpisodeListItem: View {
    let episode: Episode
    let onPlay: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onPlay) {
                EpisodeRow(episode: episode)
            }
            .buttonStyle(.plain)

            Button(action: onShowDetail) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Описание выпуска")
        }
    }
}

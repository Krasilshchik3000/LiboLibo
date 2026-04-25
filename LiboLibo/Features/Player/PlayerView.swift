import SwiftUI

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(PodcastColorService.self) private var colors
    @Environment(PodcastsRepository.self) private var repository
    @Environment(DownloadService.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    @State private var showsNotes = false
    @State private var showQueue = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            if let episode = player.currentEpisode {
                let tint = colors.tint(for: episode.podcastId)
                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    Artwork(url: episode.podcastArtworkUrl)

                    Spacer().frame(height: 24)

                    HStack(alignment: .top, spacing: 8) {
                        Titles(episode: episode) { showsNotes = true }
                        MoreMenu(episode: episode, tint: tint, path: $path)
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 22)

                    ProgressBar(tint: tint)
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 18)

                    BigControls()

                    Spacer().frame(height: 18)

                    VolumeSlider()
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 8)

                    UtilityRow(episode: episode, tint: tint) {
                        showQueue = true
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { TintBackground(tint: tint) }
                .task(id: episode.podcastId) {
                    colors.ensureTint(for: episode.podcastId, artworkUrl: episode.podcastArtworkUrl)
                }
                .sheet(isPresented: $showsNotes) {
                    EpisodeNotesSheet(episode: episode)
                }
                .sheet(isPresented: $showQueue) {
                    QueueSheetView()
                }
                .navigationDestination(for: Episode.self) { ep in
                    EpisodeDetailView(episode: ep)
                }
                .navigationDestination(for: Podcast.self) { podcast in
                    PodcastDetailView(podcast: podcast, path: $path)
                }
            }
        }
    }
}

// MARK: - Pieces

private struct Artwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Color.secondary.opacity(0.15)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 32)
    }
}

private struct Titles: View {
    let episode: Episode
    let onShowNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onShowNotes) {
                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(episode.podcastName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MoreMenu: View {
    let episode: Episode
    let tint: TintColor?
    @Binding var path: NavigationPath

    @Environment(PodcastsRepository.self) private var repository
    @Environment(DownloadService.self) private var downloads

    var body: some View {
        Menu {
            // Поделиться
            ShareLink(
                item: "\(episode.podcastName) — \(episode.title)",
                subject: Text(episode.title),
                message: Text("Слушаю в Либо-Либо")
            ) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }

            Divider()

            // Загрузка
            Button {
                downloads.toggle(episode)
            } label: {
                let downloaded = downloads.status(for: episode) == .downloaded
                Label(
                    downloaded ? "Удалить загрузку" : "Загрузить выпуск",
                    systemImage: downloaded ? "trash" : "icloud.and.arrow.down"
                )
            }

            Divider()

            // Перейти к подкасту
            if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                Button {
                    path.append(podcast)
                } label: {
                    Label("Перейти к подкасту", systemImage: "rectangle.grid.2x2")
                }
            }

            // Перейти к выпуску
            Button {
                path.append(episode)
            } label: {
                Label("Перейти к выпуску", systemImage: "play.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Apple-Podcasts-style тонкий прогресс.
private struct ProgressBar: View {
    let tint: TintColor?
    @Environment(PlayerService.self) private var player
    @State private var draggedFraction: Double?
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let progress = max(0, min(1, currentFraction))
                let trackHeight: CGFloat = isDragging ? 6 : 3

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(tint?.accent ?? Color.primary.opacity(0.7))
                        .frame(width: width * progress, height: trackHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let f = max(0, min(1, value.location.x / width))
                            draggedFraction = f
                        }
                        .onEnded { value in
                            let f = max(0, min(1, value.location.x / width))
                            if player.duration > 0 {
                                player.seek(to: f * player.duration)
                            }
                            draggedFraction = nil
                            isDragging = false
                        }
                )
                .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(height: 18)

            HStack {
                Text(PlayerService.formatTime(player.currentTime))
                Spacer()
                Text("−" + PlayerService.formatTime(max(0, player.duration - player.currentTime)))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var currentFraction: Double {
        if let dv = draggedFraction { return dv }
        return player.duration > 0 ? player.currentTime / player.duration : 0
    }
}

private struct BigControls: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 56) {
            ControlButton(systemImage: "gobackward.10", size: 30) { player.skip(by: -10) }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            ControlButton(systemImage: "goforward.10", size: 30) { player.skip(by: 10) }
        }
    }
}

private struct UtilityRow: View {
    let episode: Episode
    let tint: TintColor?
    let onShowQueue: () -> Void

    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            // Скорость воспроизведения
            PillButton(
                icon: "speedometer",
                text: player.rate != 1.0 ? PlayerService.formatRate(player.rate) : "",
                isHighlighted: player.rate != 1.0,
                tint: tint
            ) { player.cycleSpeed() }

            SleepTimerMenu(tint: tint)

            DownloadButton(episode: episode, idleTint: .primary)
                .frame(minWidth: 44, minHeight: 44)

            Button(action: onShowQueue) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Очередь")
        }
    }
}

private struct SleepTimerMenu: View {
    let tint: TintColor?
    @Environment(PlayerService.self) private var player

    var body: some View {
        let highlighted = player.sleepTimer.isActive
        let highlightColor = tint?.accent ?? Color.primary.opacity(0.7)

        Menu {
            ForEach(PlayerService.SleepTimer.allCases, id: \.self) { option in
                Button {
                    player.setSleepTimer(option)
                } label: {
                    if player.sleepTimer == option {
                        Label(option.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(option.menuLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: highlighted ? 6 : 0) {
                Image(systemName: "moon.zzz")
                if highlighted {
                    Text(player.sleepTimer.pillLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(highlighted
                          ? AnyShapeStyle(highlightColor)
                          : AnyShapeStyle(.thinMaterial))
            )
            .foregroundStyle(highlighted ? Color.white : .primary)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

// MARK: - Episode notes sheet

private struct EpisodeNotesSheet: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.podcastName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(episode.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(episode.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Описание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Components

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Кнопка состояния в UtilityRow плеера. В дефолтном состоянии — голая иконка
/// (визуально совпадает с notes/queue/download в той же строке). В активном
/// состоянии раскрывается в pill с тинтом подкаста и подписью текущего значения
/// (1.5×, 15м и т.п.) — т.е. pill = «у этой настройки сейчас не дефолт».
private struct PillButton: View {
    let icon: String
    let text: String
    let isHighlighted: Bool
    let tint: TintColor?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isHighlighted {
            let highlightedBg = tint?.accent ?? Color.primary.opacity(0.7)
            HStack(spacing: text.isEmpty ? 0 : 6) {
                Image(systemName: icon)
                    .font(.title3)
                if !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Capsule().fill(highlightedBg))
            .foregroundStyle(Color.white)
            .contentShape(Capsule())
        } else {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

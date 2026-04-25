import SwiftUI

/// Now-playing screen в духе Apple Podcasts: компактная обложка, две строки
/// заголовка, тонкий прогресс-слайдер с временем, крупные контролы, регулятор
/// громкости, нижний ряд утилит.
struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(PodcastColorService.self) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var showsNotes = false
    @State private var showQueue = false

    var body: some View {
        if let episode = player.currentEpisode {
            let tint = colors.tint(for: episode.podcastId)
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                Artwork(url: episode.podcastArtworkUrl)

                Spacer().frame(height: 24)

                Titles(episode: episode)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 22)

                ProgressBar(tint: tint)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 18)

                BigControls()

                Spacer().frame(height: 18)

                VolumeSlider()
                    .padding(.horizontal, 24)

                Spacer().frame(height: 18)

                UtilityRow(episode: episode, tint: tint) {
                    showsNotes = true
                } onShowQueue: {
                    showQueue = true
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                TintBackground(tint: tint)
            }
            .task(id: episode.podcastId) {
                colors.ensureTint(for: episode.podcastId, artworkUrl: episode.podcastArtworkUrl)
            }
            .sheet(isPresented: $showsNotes) {
                EpisodeNotesSheet(episode: episode)
            }
            .sheet(isPresented: $showQueue) {
                QueueSheetView()
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

    var body: some View {
        VStack(spacing: 4) {
            Text(episode.podcastName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(episode.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Apple-Podcasts-style тонкий прогресс. Без видимого thumb-а в idle, лёгкий
/// наплыв при скрабинге. Заполненная часть прокрашена «фирменным» цветом
/// подкаста, остаток — мягким полупрозрачным `secondary`.
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
    let onShowNotes: () -> Void
    let onShowQueue: () -> Void

    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            PillButton(
                icon: "speedometer",
                text: player.rate != 1.0 ? PlayerService.formatRate(player.rate) : "",
                isHighlighted: player.rate != 1.0,
                tint: tint
            ) { player.cycleSpeed() }

            PillButton(
                icon: "moon.zzz",
                text: player.sleepTimer.isActive ? player.sleepTimer.label : "",
                isHighlighted: player.sleepTimer.isActive,
                tint: tint
            ) { player.cycleSleepTimer() }

            DownloadButton(episode: episode, idleTint: .primary)
                .frame(minWidth: 44, minHeight: 44)

            Button(action: onShowNotes) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Описание выпуска")

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

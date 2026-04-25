import SwiftUI

/// Now-playing screen в духе Apple Podcasts: компактная обложка, две строки
/// заголовка, тонкий прогресс-слайдер с временем, крупные контролы, регулятор
/// громкости, нижний ряд утилит.
struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var showsNotes = false

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                Artwork(url: episode.podcastArtworkUrl)

                Spacer().frame(height: 24)

                Titles(episode: episode)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 22)

                ProgressBar()
                    .padding(.horizontal, 24)

                Spacer().frame(height: 18)

                BigControls()

                Spacer().frame(height: 18)

                VolumeSlider()
                    .padding(.horizontal, 24)

                Spacer().frame(height: 18)

                UtilityRow(episode: episode) {
                    showsNotes = true
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                BlurredBackdrop(url: episode.podcastArtworkUrl)
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showsNotes) {
                EpisodeNotesSheet(episode: episode)
                    .preferredColorScheme(.light)
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
                Color.white.opacity(0.1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .padding(.horizontal, 32)
    }
}

private struct Titles: View {
    let episode: Episode

    var body: some View {
        VStack(spacing: 4) {
            Text(episode.podcastName)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(episode.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Apple-Podcasts-style тонкий прогресс. Без видимого thumb-а в idle, лёгкий
/// наплыв при скрабинге.
private struct ProgressBar: View {
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
                        .fill(Color.white.opacity(0.25))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Color.white)
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
            .foregroundStyle(.white.opacity(0.85))
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
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            ControlButton(systemImage: "goforward.10", size: 30) { player.skip(by: 10) }
        }
    }
}

private struct UtilityRow: View {
    let episode: Episode
    let onShowNotes: () -> Void

    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            PillButton(
                icon: "speedometer",
                text: PlayerService.formatRate(player.rate),
                isHighlighted: player.rate != 1.0
            ) { player.cycleSpeed() }

            PillButton(
                icon: "moon.zzz",
                text: player.sleepTimer.label,
                isHighlighted: player.sleepTimer.isActive
            ) { player.cycleSleepTimer() }

            DownloadButton(episode: episode, idleTint: .white)
                .frame(minWidth: 44, minHeight: 44)

            Button(action: onShowNotes) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Описание выпуска")
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

private struct BlurredBackdrop: View {
    let url: URL?

    var body: some View {
        ZStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill().blur(radius: 80, opaque: true)
                default:
                    Color.gray.opacity(0.1)
                }
            }
            .clipped()
            .ignoresSafeArea()

            Color.black.opacity(0.25).ignoresSafeArea()
        }
    }
}

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PillButton: View {
    let icon: String
    let text: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.liboRed.opacity(0.85) : Color.white.opacity(0.18))
            )
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}


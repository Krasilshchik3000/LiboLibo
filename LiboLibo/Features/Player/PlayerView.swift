import SwiftUI

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var showsNotes = false

    var body: some View {
        if let episode = player.currentEpisode {
            ZStack {
                BlurredBackdrop(url: episode.podcastArtworkUrl)

                VStack(spacing: 20) {
                    AsyncImage(url: episode.podcastArtworkUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.white.opacity(0.1)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .padding(.horizontal, 40)
                    .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text(episode.podcastName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(episode.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    ProgressSlider()
                        .padding(.horizontal, 32)

                    HStack(spacing: 44) {
                        ControlButton(systemImage: "gobackward.10", size: 32) { player.skip(by: -10) }

                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        ControlButton(systemImage: "goforward.10", size: 32) { player.skip(by: 10) }
                    }

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

                        Button {
                            showsNotes = true
                        } label: {
                            Image(systemName: "doc.text")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Описание выпуска")
                    }

                    Spacer(minLength: 16)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showsNotes) {
                EpisodeNotesSheet(episode: episode)
                    .preferredColorScheme(.light)
            }
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
                Text(text).font(.subheadline).fontWeight(.medium)
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

private struct ProgressSlider: View {
    @Environment(PlayerService.self) private var player
    @State private var draggedValue: Double?

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: {
                        if let dv = draggedValue { return dv }
                        return player.duration > 0 ? player.currentTime / player.duration : 0
                    },
                    set: { draggedValue = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing, let dv = draggedValue, player.duration > 0 {
                        player.seek(to: dv * player.duration)
                        draggedValue = nil
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(PlayerService.formatTime(player.currentTime))
                Spacer()
                Text(PlayerService.formatTime(max(0, player.duration - player.currentTime)))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

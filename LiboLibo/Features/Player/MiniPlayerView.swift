import SwiftUI

/// Содержимое мини-плеера для `tabViewBottomAccessory` (iOS 26).
/// Без собственного фона — хост даёт liquid-glass подложку.
struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        if let episode = player.currentEpisode {
            HStack(spacing: 12) {
                AsyncImage(url: episode.podcastArtworkUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        content: Text(episode.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    )
                    MarqueeText(
                        content: Text(episode.podcastName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.liboRed)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

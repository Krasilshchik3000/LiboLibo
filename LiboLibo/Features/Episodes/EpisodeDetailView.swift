import SwiftUI

/// Экран отдельного выпуска: обложка, метаданные, кнопки «Слушать» / «Скачать»
/// и полное описание из RSS.
struct EpisodeDetailView: View {
    let episode: Episode

    @Environment(PlayerService.self) private var player
    @Environment(PodcastColorService.self) private var colors

    var body: some View {
        let tint = colors.tint(for: episode.podcastId)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions(tint: tint)
                description
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { TintBackground(tint: tint) }
        .tint(.primary)
        .navigationTitle("Выпуск")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: episode.podcastId) {
            colors.ensureTint(for: episode.podcastId, artworkUrl: episode.podcastArtworkUrl)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: episode.podcastArtworkUrl) { phase in
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
                Text(episode.podcastName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(episode.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text(episode.pubDate, style: .date)
                    if let dur = episode.duration {
                        Text("·")
                        Text(formatDuration(dur))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func actions(tint: TintColor?) -> some View {
        if episode.isPlayable {
            HStack(spacing: 12) {
                Button {
                    player.play(episode)
                } label: {
                    Label("Слушать", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint?.accent ?? .accentColor)

                DownloadButton(episode: episode, style: .button)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        } else {
            // Премиум-эпизод без активного entitlement: тизер.
            Label("Доступно по подписке", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.4))
                }
        }
    }

    @ViewBuilder
    private var description: some View {
        if !episode.summary.isEmpty {
            Text(episode.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.top, 4)
                .textSelection(.enabled)
        }
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h) ч \(m) мин" }
    return "\(m) мин"
}

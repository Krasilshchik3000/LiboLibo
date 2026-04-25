import SwiftUI

/// Карточка выпуска в стиле Apple Podcasts: крупная обложка слева, заголовок —
/// `.headline`, превью описания — `.subheadline` (.secondary), внизу — иконка
/// загрузки и метаданные (дата · длительность).
///
/// Тексты НЕ обрезаются — показываем полностью.
struct EpisodeRow: View {
    let episode: Episode
    var showsPreview: Bool = true

    var body: some View {
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
                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundStyle(.liboRed)

                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if showsPreview {
                    let preview = episode.summary.firstSentences(maxCount: 2)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 8) {
                    DownloadButton(episode: episode, style: .icon)
                        .frame(width: 28, height: 28, alignment: .leading)

                    Text(metadataLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var metadataLine: String {
        var parts: [String] = []
        parts.append(episode.pubDate.formatted(date: .abbreviated, time: .omitted))
        if let dur = episode.duration {
            parts.append(formatDuration(dur))
        }
        return parts.joined(separator: " · ")
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h) ч \(m) мин" }
    return "\(m) мин"
}

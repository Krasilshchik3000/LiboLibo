import SwiftUI

/// Единый компонент строки подкаста: используется в `PodcastsView` (.regular,
/// крупная — обложка 80, имя + 2 строки описания), а также в `ProfileView`
/// и `SearchView` (.compact — обложка 56, имя + одна строка артиста).
/// До этого в проекте было три отдельных копии, каждая с чуть разным
/// шрифтом/радиусом — собрали в одну.
struct PodcastRow: View {
    enum Density {
        case regular
        case compact
    }

    let podcast: Podcast
    var density: Density = .regular

    var body: some View {
        HStack(alignment: density == .regular ? .top : .center, spacing: 12) {
            AsyncImage(url: podcast.artworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(
                cornerRadius: density == .regular ? Theme.radiusMedium : Theme.radiusSmall
            ))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.name)
                    .font(Theme.itemTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(density == .regular ? nil : 1)

                if density == .regular {
                    if let desc = podcast.description {
                        let preview = desc.firstSentences(maxCount: 2)
                        if !preview.isEmpty {
                            Text(preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    HStack(spacing: 8) {
                        SubscribeButton(podcast: podcast)
                    }
                    .padding(.top, 4)
                } else {
                    Text(podcast.artist)
                        .font(Theme.itemMeta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, density == .regular ? 8 : 2)
        .contentShape(Rectangle())
    }

    private var artworkSize: CGFloat {
        density == .regular ? 80 : 56
    }
}

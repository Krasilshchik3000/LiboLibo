import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PodcastColorService.self) private var colors

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !active.isEmpty {
                    Section("Выходят сейчас") {
                        ForEach(active) { podcast in
                            PodcastListItem(podcast: podcast) { path.append(podcast) }
                        }
                    }
                }
                if !recent.isEmpty {
                    Section("Недавно выходили") {
                        ForEach(recent) { podcast in
                            PodcastListItem(podcast: podcast) { path.append(podcast) }
                        }
                    }
                }
                if !dormant.isEmpty {
                    Section("Давно не выходят") {
                        ForEach(dormant) { podcast in
                            PodcastListItem(podcast: podcast) { path.append(podcast) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Подкасты")
            .navigationDestination(for: Podcast.self) { podcast in
                PodcastDetailView(podcast: podcast, path: $path)
            }
        }
        .task(id: repository.podcasts.count) {
            for podcast in repository.podcasts {
                colors.ensureTint(for: podcast.id, artworkUrl: podcast.artworkUrl)
            }
        }
    }

    // MARK: - Segmentation

    /// Иноязычные версии шоу (Harbin DE, The Adults in the Room EN, The Naked
    /// Mole Rat EN) скрыты с этого экрана: у них и название, и описание не
    /// содержат кириллицы. Если такой подкаст обогатится русским описанием
    /// в RSS — он автоматически вернётся в список.
    private var russianPodcasts: [Podcast] {
        repository.podcasts.filter { $0.name.containsCyrillic || ($0.description?.containsCyrillic ?? false) }
    }

    private var active: [Podcast] {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        return russianPodcasts
            .filter { ($0.lastEpisodeDate ?? .distantPast) >= cutoff }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var recent: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        let threeAgo = Date().addingTimeInterval(-90 * 86400)
        return russianPodcasts
            .filter {
                guard let d = $0.lastEpisodeDate else { return false }
                return d < threeAgo && d >= twelveAgo
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var dormant: [Podcast] {
        let twelveAgo = Date().addingTimeInterval(-365 * 86400)
        return russianPodcasts
            .filter { (p: Podcast) -> Bool in
                guard let d = p.lastEpisodeDate else { return true }
                return d < twelveAgo
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private extension String {
    var containsCyrillic: Bool {
        contains { $0.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
    }
}

/// Строка списка подкастов: тап по основной зоне открывает экран подкаста,
/// маленькая иконка-кнопка слева внизу — toggle подписки (по аналогии с
/// `DownloadButton` у эпизодов).
private struct PodcastListItem: View {
    let podcast: Podcast
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PodcastRow(podcast: podcast)
        }
        .buttonStyle(.plain)
    }
}

/// Типографика как в `EpisodeListItem` (Фид):
/// .headline — название, .subheadline — превью описания. Внизу — кнопка
/// подписки в формате иконки.
private struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: podcast.artworkUrl) { phase in
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
                Text(podcast.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

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
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Иконка-toggle подписки. Логика как у `DownloadButton`: подписан —
/// заполненная галочка в брендовом цвете, не подписан — контурный плюс
/// в `.secondary`.
private struct SubscribeButton: View {
    let podcast: Podcast
    @Environment(SubscriptionsService.self) private var subscriptions

    var body: some View {
        Button {
            subscriptions.toggle(podcast)
        } label: {
            Image(systemName: subscriptions.isSubscribed(podcast)
                  ? "checkmark.circle.fill"
                  : "plus.circle")
                .font(.title3)
                .foregroundStyle(subscriptions.isSubscribed(podcast) ? Color.liboRed : .secondary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subscriptions.isSubscribed(podcast) ? "Отписаться" : "Подписаться")
    }
}

#Preview {
    PodcastsView()
        .environment(PodcastsRepository())
}

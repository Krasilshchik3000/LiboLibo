import SwiftUI

struct QueueSheetView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    previousSection
                    nowPlayingSection
                    upNextSection
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    proxy.scrollTo("nowPlaying", anchor: .top)
                }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var previousSection: some View {
        let items = episodesBefore
        if !items.isEmpty {
            Section("Предыдущие") {
                ForEach(items) { episode in
                    Button {
                        player.play(episode)
                        dismiss()
                    } label: {
                        QueueRow(episode: episode)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let current = player.currentEpisode {
            Section("Сейчас играет") {
                HStack(spacing: 12) {
                    QueueRow(episode: current)
                    Spacer(minLength: 0)
                    if player.isPlaying {
                        Image(systemName: "waveform")
                            .symbolEffect(.pulse)
                            .foregroundStyle(.tint)
                            .font(.subheadline)
                    } else {
                        Image(systemName: "pause.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
                .id("nowPlaying")
            }
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        let items = episodesAfter
        if !items.isEmpty {
            Section("Далее") {
                ForEach(items) { episode in
                    Button {
                        player.play(episode)
                        dismiss()
                    } label: {
                        QueueRow(episode: episode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var episodesBefore: [Episode] {
        guard let current = player.currentEpisode,
              let idx = player.feedContext.firstIndex(where: { $0.id == current.id }),
              idx > 0 else { return [] }
        return Array(player.feedContext.prefix(idx))
    }

    private var episodesAfter: [Episode] {
        guard let current = player.currentEpisode,
              let idx = player.feedContext.firstIndex(where: { $0.id == current.id }),
              idx + 1 < player.feedContext.count else { return [] }
        return Array(player.feedContext.suffix(from: idx + 1))
    }
}

private struct QueueRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: episode.podcastArtworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(episode.title)
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

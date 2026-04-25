import SwiftUI

struct QueueSheetView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var localAfterItems: [Episode] = []
    @State private var draggedID: String? = nil
    @State private var dragStartIndex: Int? = nil

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
                    localAfterItems = episodesAfter
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
        .onChange(of: episodesAfter) { _, newItems in
            guard draggedID == nil else { return }
            localAfterItems = newItems
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
        if !localAfterItems.isEmpty {
            Section("Далее") {
                ForEach(localAfterItems) { episode in
                    HStack(spacing: 0) {
                        Button {
                            player.play(episode)
                            dismiss()
                        } label: {
                            QueueRow(episode: episode)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .frame(width: 44)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                    .onChanged { value in
                                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                                        if draggedID == nil {
                                            draggedID = episode.id
                                            dragStartIndex = localAfterItems.firstIndex(where: { $0.id == episode.id })
                                        }
                                        guard draggedID == episode.id, let startIdx = dragStartIndex else { return }
                                        let rowHeight: CGFloat = 52
                                        let delta = Int((value.translation.height / rowHeight).rounded())
                                        let newIdx = max(0, min(localAfterItems.count - 1, startIdx + delta))
                                        guard let currentIdx = localAfterItems.firstIndex(where: { $0.id == episode.id }),
                                              newIdx != currentIdx else { return }
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            localAfterItems.move(
                                                fromOffsets: IndexSet(integer: currentIdx),
                                                toOffset: newIdx > currentIdx ? newIdx + 1 : newIdx
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        player.setQueueAfter(localAfterItems)
                                        draggedID = nil
                                        dragStartIndex = nil
                                    }
                            )
                    }
                    .opacity(draggedID == episode.id ? 0.5 : 1.0)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            player.removeFromQueue(episode)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
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

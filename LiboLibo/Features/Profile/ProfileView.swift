import SwiftUI

struct ProfileView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(SubscriptionsService.self) private var subscriptions
    @Environment(HistoryService.self) private var history
    @Environment(DownloadService.self) private var downloads
    @Environment(PlayerService.self) private var player
    @Environment(AdaptyService.self) private var adapty

    /// Колбэк от RootView для переключения на таб «Подкасты» из CTA в пустом
    /// состоянии «Подписок». В Preview по умолчанию nil — кнопка просто
    /// не показывается.
    var onOpenPodcasts: (() -> Void)? = nil

    @State private var path = NavigationPath()
    @State private var showsClearHistoryAlert = false
    @State private var showsPaywall = false
    @State private var restoreAlert: RestoreAlertState?
    @State private var isRestoring = false

    private var subscribedPodcasts: [Podcast] {
        repository.podcasts.filter { subscriptions.isSubscribed($0) }
    }

    private var recentFromSubscriptions: [Episode] {
        let ids = subscriptions.subscribedIds
        guard !ids.isEmpty else { return [] }
        return Array(
            repository.allEpisodes
                .filter { ids.contains($0.podcastId) }
                .prefix(20)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                premiumSection
                subscriptionsSection
                if !downloads.items.isEmpty {
                    downloadedSection
                }
                if !recentFromSubscriptions.isEmpty {
                    recentSection
                }
                if !history.items.isEmpty {
                    historySection
                }
                if subscribedPodcasts.isEmpty
                    && history.items.isEmpty
                    && downloads.items.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("Моё")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0, path: $path) }
            .navigationDestination(for: Episode.self) { EpisodeDetailView(episode: $0) }
            .alert("Очистить историю?", isPresented: $showsClearHistoryAlert) {
                Button("Очистить", role: .destructive) {
                    history.clearAll()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Список прослушанных выпусков будет удалён.")
            }
            .alert(item: $restoreAlert) { state in
                Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showsPaywall) {
                AdaptyPaywallView(
                    placementId: "default",
                    onPurchase: {
                        showsPaywall = false
                        Task {
                            if await adapty.refreshEntitlement() {
                                await repository.loadAllEpisodes()
                            }
                        }
                    },
                    onClose: { showsPaywall = false }
                )
            }
        }
    }

    private var premiumSection: some View {
        Section("Премиум") {
            if adapty.isPremium {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Премиум активен", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.liboRed)
                        .font(.headline)
                    if let expiresAt = adapty.expiresAt {
                        Text("Действует до \(expiresAt.formatted(date: .long, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Бессрочный доступ")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Label("Управлять подпиской", systemImage: "arrow.up.forward.app")
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Премиум-подписка")
                        .font(.headline)
                    Text("Бонусные и эксклюзивные выпуски «Либо-Либо».")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button {
                    showsPaywall = true
                } label: {
                    Label("Оформить", systemImage: "lock.shield.fill")
                        .foregroundStyle(.liboRed)
                }

                Button {
                    Task { await runRestore() }
                } label: {
                    if isRestoring {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Восстанавливаем…")
                        }
                    } else {
                        Label("Восстановить покупки", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRestoring)
            }
        }
    }

    private func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        let outcome = await adapty.restorePurchases()
        switch outcome {
        case .restored:
            await repository.loadAllEpisodes()
            restoreAlert = RestoreAlertState(
                title: "Подписка восстановлена",
                message: "Премиум-выпуски снова доступны."
            )
        case .nothingToRestore:
            restoreAlert = RestoreAlertState(
                title: "Покупок не найдено",
                message: "На этом Apple ID нет активных подписок «Либо-Либо»."
            )
        case .failed:
            restoreAlert = RestoreAlertState(
                title: "Не получилось",
                message: "Проверь интернет и попробуй ещё раз."
            )
        }
    }

    private var subscriptionsSection: some View {
        Section("Подписки") {
            if subscribedPodcasts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Подпишись на подкаст — он появится здесь, и его выпуски будут в «Свежее у подписок».")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if let onOpenPodcasts {
                        Button(action: onOpenPodcasts) {
                            Text("Открыть подкасты")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.liboRed)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(subscribedPodcasts) { podcast in
                    NavigationLink(value: podcast) {
                        HStack(spacing: 12) {
                            AsyncImage(url: podcast.artworkUrl) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.secondary.opacity(0.15)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(podcast.name)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var downloadedSection: some View {
        Section("Скачано") {
            ForEach(downloads.items) { item in
                let episode = item.asEpisode
                EpisodeListItem(
                    episode: episode,
                    onPlay: { player.play(episode) },
                    onShowDetail: { path.append(episode) },
                    onPlayNext: { player.playNext(episode) },
                    onNavigateToPodcast: {
                        if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                            path.append(podcast)
                        }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        downloads.deleteDownload(episode)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Свежее у подписок") {
            ForEach(recentFromSubscriptions) { episode in
                EpisodeListItem(
                    episode: episode,
                    onPlay: {
                        let context = repository.allEpisodes
                            .filter { $0.podcastId == episode.podcastId }
                            .sorted { $0.pubDate < $1.pubDate }
                        player.play(episode, context: context)
                    },
                    onShowDetail: { path.append(episode) },
                    onPlayNext: { player.playNext(episode) },
                    onNavigateToPodcast: {
                        if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                            path.append(podcast)
                        }
                    }
                )
            }
        }
    }

    private var historySection: some View {
        Section {
            ForEach(history.items) { item in
                let episode = history.episode(for: item)
                EpisodeListItem(
                    episode: episode,
                    onPlay: { player.play(episode) },
                    onShowDetail: { path.append(episode) },
                    onPlayNext: { player.playNext(episode) },
                    onNavigateToPodcast: {
                        if let podcast = repository.podcasts.first(where: { $0.id == episode.podcastId }) {
                            path.append(podcast)
                        }
                    }
                )
            }
        } header: {
            HStack {
                Text("История")
                Spacer()
                Button {
                    showsClearHistoryAlert = true
                } label: {
                    Text("Очистить")
                        .font(.footnote)
                        .foregroundStyle(.liboRed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct RestoreAlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "Здесь будет твоя жизнь в подкастах",
                systemImage: "person.crop.circle",
                description: Text("Подписки, скачанные выпуски и история прослушиваний появятся, как только начнёшь слушать.")
            )
            .listRowBackground(Color.clear)
            .padding(.vertical, 24)
        }
    }
}

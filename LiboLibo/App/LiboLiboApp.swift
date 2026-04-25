import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()
    @State private var subscriptions = SubscriptionsService()
    @State private var history = HistoryService()
    @State private var downloads = DownloadService()
    @State private var player = PlayerService()
    @State private var colors = PodcastColorService()
    @State private var adapty = AdaptyService()

    @State private var showsWelcomePaywall = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(subscriptions)
                .environment(history)
                .environment(downloads)
                .environment(player)
                .environment(colors)
                .environment(adapty)
                .tint(.liboRed)
                .task {
                    // Проводник profile_id для всех бэкенд-запросов: бэк по
                    // `X-Adapty-Profile-Id` решает, отдавать ли `audio_url` для
                    // премиум-эпизодов.
                    APIClient.shared.attachProfileIdProvider { [weak adapty] in
                        adapty?.profileId
                    }

                    // История прослушиваний.
                    player.onPlay = { [weak history] episode in
                        history?.record(episode)
                    }
                    // Если выпуск скачан — играть с диска.
                    player.localUrlResolver = { episode in
                        DownloadService.localUrl(for: episode)
                    }
                    // Прогреваем цвета обложек: плеер из «Фида» сразу знает тинт.
                    for podcast in repository.podcasts {
                        colors.ensureTint(for: podcast.id, artworkUrl: podcast.artworkUrl)
                    }

                    // Cold-start: поднять Adapty SDK + дёрнуть refresh.
                    // Если изменился `isPremium` — перегружаем ленту, чтобы
                    // `audio_url` пришёл свежий.
                    await adapty.activate()
                    if await adapty.refreshEntitlement() {
                        await repository.loadAllEpisodes()
                    }

                    // Welcome-paywall раз в 7 дней, пока нет подписки и SDK
                    // активирован. До подключения SPM `isActivated == false` —
                    // welcome не показывается.
                    if adapty.shouldShowWelcomePaywall {
                        showsWelcomePaywall = true
                        adapty.markWelcomePaywallShown()
                    }
                }
                .sheet(isPresented: $showsWelcomePaywall) {
                    AdaptyPaywallView(
                        placementId: "default",
                        onPurchase: {
                            showsWelcomePaywall = false
                            Task {
                                if await adapty.refreshEntitlement() {
                                    await repository.loadAllEpisodes()
                                }
                            }
                        },
                        onClose: { showsWelcomePaywall = false }
                    )
                }
        }
    }
}

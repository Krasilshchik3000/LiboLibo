import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()
    @State private var subscriptions = SubscriptionsService()
    @State private var history = HistoryService()
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(subscriptions)
                .environment(history)
                .environment(player)
                .onAppear {
                    // Связываем плеер и историю: каждый старт нового эпизода
                    // записывается в журнал прослушиваний.
                    player.onPlay = { [weak history] episode in
                        history?.record(episode)
                    }
                }
        }
    }
}

import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false

    var body: some View {
        tabContainer
            .sheet(isPresented: $showFullPlayer) {
                PlayerView()
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder
    private var tabContainer: some View {
        if #available(iOS 26.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
    }

    @available(iOS 26.0, *)
    private var modernTabView: some View {
        TabView {
            tabs
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if player.currentEpisode != nil {
                MiniPlayerView()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullPlayer = true }
            }
        }
    }

    private var legacyTabView: some View {
        TabView {
            tabs
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentEpisode != nil {
                MiniPlayerView()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.separator.opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { showFullPlayer = true }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: player.currentEpisode?.id)
    }

    @ViewBuilder
    private var tabs: some View {
        FeedView()
            .tabItem {
                Label("Фид", systemImage: "list.dash")
            }

        PodcastsView()
            .tabItem {
                Label("Подкасты", systemImage: "rectangle.grid.2x2")
            }

        SearchView()
            .tabItem {
                Label("Поиск", systemImage: "magnifyingglass")
            }

        ProfileView()
            .tabItem {
                Label("Моё", systemImage: "person.crop.circle")
            }
    }
}

#Preview {
    RootView()
        .environment(PodcastsRepository())
        .environment(SubscriptionsService())
        .environment(HistoryService())
        .environment(PlayerService())
}

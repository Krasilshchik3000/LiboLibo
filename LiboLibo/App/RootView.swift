import SwiftUI

struct RootView: View {
    enum SelectedTab: Hashable {
        case feed, podcasts, profile, search
    }

    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false
    @State private var selectedTab: SelectedTab = .feed

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

    // MARK: - iOS 26+: Tab API + tabViewBottomAccessory only when episode loaded

    @available(iOS 26.0, *)
    @ViewBuilder
    private var modernTabView: some View {
        if player.currentEpisode != nil {
            TabView(selection: $selectedTab) {
                modernTabs
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MiniPlayerView()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullPlayer = true }
            }
        } else {
            TabView(selection: $selectedTab) {
                modernTabs
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        }
    }

    @available(iOS 18.0, *)
    @TabContentBuilder<SelectedTab>
    private var modernTabs: some TabContent<SelectedTab> {
        Tab("Фид", systemImage: "list.dash", value: SelectedTab.feed) {
            FeedView()
        }
        Tab("Подкасты", systemImage: "rectangle.grid.2x2", value: SelectedTab.podcasts) {
            PodcastsView()
        }
        Tab("Моё", systemImage: "person.crop.circle", value: SelectedTab.profile) {
            ProfileView(onOpenPodcasts: { selectedTab = .podcasts })
        }
        Tab(value: SelectedTab.search, role: .search) {
            SearchView()
        }
    }

    // MARK: - iOS 18–25: same tabs, legacy bottom accessory

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            modernTabs
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
}

#Preview {
    RootView()
        .environment(PodcastsRepository())
        .environment(SubscriptionsService())
        .environment(HistoryService())
        .environment(PlayerService())
}

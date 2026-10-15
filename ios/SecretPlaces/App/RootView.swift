import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack { DiscoverView() }
                .tabItem { Label("Discover", systemImage: "sparkles") }
            NavigationStack { EventsView() }
                .tabItem { Label("Events", systemImage: "ticket") }
            NavigationStack { MapExploreView() }
                .tabItem { Label("Map", systemImage: "map") }
            NavigationStack { SavedView() }
                .tabItem { Label("Saved", systemImage: "bookmark") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.accent)
        .background(Theme.bg)
        .overlay(alignment: .top) {
            if let a = env.celebratedAchievement {
                AchievementToast(achievement: a)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { env.celebratedAchievement = nil }
                    .task(id: a.id) {
                        Haptics.success()
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation { env.celebratedAchievement = nil }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: env.celebratedAchievement?.id)
    }
}

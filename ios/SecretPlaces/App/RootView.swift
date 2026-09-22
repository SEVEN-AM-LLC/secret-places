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
    }
}

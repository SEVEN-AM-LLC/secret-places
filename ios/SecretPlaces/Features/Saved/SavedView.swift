import SwiftUI

/// "My Secrets" — Unlocked / Saved / Visited / Want to Visit.
struct SavedView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @State private var tab: Tab = .unlocked
    @State private var cache: [String: PlaceTeaser] = [:]
    @State private var unlockedIds: Set<String> = []
    @State private var loading = false
    @State private var showSignIn = false

    enum Tab: String, CaseIterable { case unlocked = "Unlocked", saved = "Saved", visited = "Visited", want = "Want to Visit" }

    private var ids: [String] {
        switch tab {
        case .unlocked: return Array(unlockedIds)
        case .saved: return Array(env.savedIds)
        case .visited: return env.placeStatuses.filter { $0.value == .visited }.map { $0.key }
        case .want: return env.placeStatuses.filter { $0.value == .wantToVisit }.map { $0.key }
        }
    }

    var body: some View {
        ScrollView {
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                .pickerStyle(.segmented).padding(14)

            if !auth.isSignedIn {
                signInPrompt
            } else if loading {
                LoadingView()
            } else if ids.isEmpty {
                EmptyStateView(icon: emptyIcon, title: "Nothing here yet", message: emptyMessage)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(ids, id: \.self) { id in
                        if let p = cache[id] {
                            NavigationLink(value: p) { PlaceCard(place: p, isSaved: env.savedIds.contains(id)) }.buttonStyle(.plain)
                        }
                    }
                }.padding(14)
            }
        }
        .background(Theme.bg)
        .navigationTitle("My Secrets")
        .withAppDestinations()
        .sheet(isPresented: $showSignIn) { SignInView() }
        .task { await reload() }
        .onChange(of: tab) { _, _ in Task { await hydrate() } }
        .refreshable { await reload() }
    }

    private var signInPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(Theme.textMuted)
            Text("Sign in to see your secrets").font(.headline).foregroundStyle(Theme.text)
            Text("Your unlocked places, saves and visits sync to your account.").font(.subheadline).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            Button("Sign in with Apple") { showSignIn = true }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
        }.padding(30)
    }

    private var emptyIcon: String {
        switch tab { case .unlocked: return "lock.open"; case .saved: return "bookmark"; case .visited: return "checkmark.seal"; case .want: return "heart" }
    }
    private var emptyMessage: LocalizedStringKey {
        switch tab {
        case .unlocked: return "Unlock a secret place to keep it here forever."
        case .saved: return "Save places you want to remember."
        case .visited: return "Mark places visited to build your map."
        case .want: return "Add places to your want-to-visit list."
        }
    }

    private func reload() async {
        guard auth.isSignedIn else { return }
        loading = true
        await env.refreshUserState()
        unlockedIds = (try? await env.entitlements.unlockedPlaceIds()) ?? []
        await hydrate()
        loading = false
    }

    private func hydrate() async {
        let need = ids.filter { cache[$0] == nil }
        guard !need.isEmpty else { return }
        if let fetched = try? await env.places.byIds(need) {
            for p in fetched { cache[p.id] = p }
        }
    }
}

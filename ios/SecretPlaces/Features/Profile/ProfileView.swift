import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var location: LocationService
    @State private var showSignIn = false
    @State private var showOnboarding = false
    @State private var showDeleteConfirm = false
    @State private var restoreMessage: String?
    @State private var languageSelection = AppLanguage.current.rawValue
    @State private var showRestartPrompt = false

    var body: some View {
        List {
            Section {
                if auth.isSignedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(auth.session?.email ?? "Signed in").font(.headline)
                            Text("Synced across your devices").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button { showSignIn = true } label: { Label("Sign in with Apple", systemImage: "apple.logo") }
                }
            }

            Section { SecretsPassport() } header: { Text("Your secrets") }
                .listRowBackground(Theme.surface)

            Section("Personalize") {
                Button { showOnboarding = true } label: { Label("Your interests", systemImage: "slider.horizontal.3") }
                Picker(selection: $languageSelection) {
                    ForEach(AppLanguage.allCases) { lang in
                        // "System" localizes; the two endonyms stay verbatim in both locales.
                        (lang == .system ? Text("System") : Text(verbatim: lang.label)).tag(lang.rawValue)
                    }
                } label: { Label("Language", systemImage: "globe") }
                .onChange(of: languageSelection) { _, new in
                    guard let lang = AppLanguage(rawValue: new), lang != AppLanguage.current else { return }
                    lang.apply()
                    showRestartPrompt = true
                }
                Toggle(isOn: locationBinding) { Label("Location access", systemImage: "location") }
                    .disabled(location.authorization != .notDetermined)
            }

            Section("Purchases") {
                Button { Task { await restore() } } label: { Label("Restore purchases", systemImage: "arrow.clockwise") }
                if let restoreMessage { Text(restoreMessage).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Notifications") { NotificationPrefsView() }

            Section("Privacy") {
                NavigationLink { PrivacyView() } label: { Label("Privacy & data", systemImage: "hand.raised") }
                Button { Task { await DiskCache.shared.clearAll() } } label: { Label("Clear offline cache", systemImage: "trash") }
            }

            if auth.isSignedIn {
                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete account", systemImage: "person.crop.circle.badge.xmark") }
                    Button { auth.signOut(); env.entitlements.clear(); Task { await env.refreshUserState() } } label: { Text("Sign out") }
                }
            }

            Section { Text("Secret Places v1.0.1").font(.caption).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Profile")
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete everything", role: .destructive) { Task { try? await env.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes your account, saves, visits and unlock records. This cannot be undone.") }
        .alert("Language changed", isPresented: $showRestartPrompt) {
            Button("Restart now", role: .destructive) { exit(0) }
            Button("Later", role: .cancel) {}
        } message: { Text("Restart the app to apply the new language everywhere.") }
    }

    private var locationBinding: Binding<Bool> {
        Binding(get: { location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways },
                set: { _ in if location.authorization == .notDetermined { location.requestPermission() } })
    }

    private func restore() async {
        do { try await purchases.restore(); restoreMessage = "Restored. Your unlocks are up to date." }
        catch AppError.notAuthenticated { restoreMessage = "Sign in first to restore across devices."; showSignIn = true }
        catch { restoreMessage = "Couldn't restore right now." }
    }
}

/// Notification preferences, stored in notification_preferences (RLS: owner).
struct NotificationPrefsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @State private var prefs = Prefs()

    struct Prefs: Codable, Equatable {
        var nearbyNew = true, savedCityNew = true, freeToday = true, neighborhoodCollections = false, tripRecommendations = false
    }

    var body: some View {
        Group {
            Toggle("New places nearby", isOn: $prefs.nearbyNew)
            Toggle("New in my saved city", isOn: $prefs.savedCityNew)
            Toggle("Free Secret Today", isOn: $prefs.freeToday)
            Toggle("Neighborhood collections", isOn: $prefs.neighborhoodCollections)
            Toggle("Trip recommendations", isOn: $prefs.tripRecommendations)
        }
        .disabled(!auth.isSignedIn)
        .onChange(of: prefs) { _, _ in Task { await save() } }
    }

    private func save() async {
        guard let uid = auth.currentUserId else { return }
        struct Body: Encodable {
            let userId: String; let nearbyNew: Bool; let savedCityNew: Bool
            let freeToday: Bool; let neighborhoodCollections: Bool; let tripRecommendations: Bool
        }
        struct Row: Decodable { let userId: String? }
        _ = try? await env.client.insert("notification_preferences",
            body: [Body(userId: uid, nearbyNew: prefs.nearbyNew, savedCityNew: prefs.savedCityNew,
                        freeToday: prefs.freeToday, neighborhoodCollections: prefs.neighborhoodCollections,
                        tripRecommendations: prefs.tripRecommendations)],
            as: [Row].self, upsert: true)
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy & data").font(.title2.bold())
                Text("We collect the minimum needed to run Secret Places. Your saves, visits and unlocks are tied to your account so they sync across devices.")
                Text("Location is optional. If you allow it, we use your position only to show nearby places — coarse, never precise, GPS is never sent to analytics.")
                Text("You can clear your offline cache anytime, and deleting your account removes your personal data (profile, saves, visits, unlock records) from our database.")
                Divider().padding(.vertical, 6)
                Text("Place data © OpenStreetMap contributors, available under the Open Database License (ODbL).")
                    .font(.footnote)
                Text("Photos marked © come from Wikimedia Commons; each shows its author and licence. Awards are taken from Wikidata — check the current guide before booking.")
                    .font(.footnote)
            }.foregroundStyle(Theme.textMuted).padding()
        }.background(Theme.bg).navigationTitle("Privacy")
    }
}

/// The user's collection: how many secrets they've found, where, and the badges earned on the way.
struct SecretsPassport: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        let visited = env.visitedPlaces
        let byCity = Dictionary(grouping: visited, by: { $0.cityId ?? "" })
        let badges = env.achievements
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                stat("\(visited.count)", "found")
                stat("\(byCity.keys.filter { !$0.isEmpty }.count)", "cities")
                stat("\(badges.filter(\.earned).count)/\(badges.count)", "badges")
            }
            if !auth.isSignedIn {
                Text("Sign in and tap \u{201C}I've been here\u{201D} at a secret to start your collection.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else if visited.isEmpty {
                Text("Tap \u{201C}I've been here\u{201D} when you find a secret — your cities and badges collect here.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
            ForEach(byCity.keys.sorted(), id: \.self) { cityId in
                if let city = env.cities.first(where: { $0.id == cityId }) {
                    let p = env.progress(cityId: cityId)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(env.country(for: city.countryId)?.emojiFlag ?? "") \(city.title)").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(p.found) of \(p.total)").font(.caption).foregroundStyle(Theme.accent)
                        }
                        ProgressView(value: Double(p.found), total: Double(max(p.total, 1))).tint(Theme.accent)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10, alignment: .top)], spacing: 12) {
                ForEach(badges) { b in
                    VStack(spacing: 6) {
                        Image(systemName: b.symbol).font(.title3)
                            .foregroundStyle(b.earned ? Color.black : Theme.textMuted.opacity(0.5))
                            .frame(width: 46, height: 46)
                            .background(b.earned ? Theme.accent : Theme.surface2, in: Circle())
                        Text(b.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
                            .foregroundStyle(b.earned ? Theme.text : Theme.textMuted)
                        Text(b.detail).font(.system(size: 9)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(b.earned ? "Earned" : "Not yet"))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(26)).foregroundStyle(Theme.text)
            Text(label).font(.caption).foregroundStyle(Theme.textMuted)
        }.frame(maxWidth: .infinity)
    }
}

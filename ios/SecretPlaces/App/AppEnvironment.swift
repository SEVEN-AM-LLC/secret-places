import Foundation
import SwiftUI
import CoreLocation

/// Dependency container. Constructed once and injected via the SwiftUI environment.
/// Uses protocols for every service so tests/previews can inject mocks.
@MainActor
final class AppEnvironment: ObservableObject {
    let client: SupabaseClient
    let auth: AuthStore
    let analytics: AnalyticsService

    let places: PlaceRepository
    let geo: GeoRepository
    let categoriesRepo: CategoryRepository
    let collections: CollectionsRepository
    let search: SearchService
    let saved: SavedPlacesRepository
    let ratings: RatingsRepository
    let reports: ReportsRepository
    let events: EventsRepository
    let routes: RoutesRepository

    let entitlements: SupabaseEntitlementService
    let purchases: PurchaseService
    let location: LocationService

    /// Cached categories (backend-configured, not hardcoded).
    @Published var categories: [Category] = []
    @Published var savedIds: Set<String> = []

    /// Cities that have at least one published place, and how many each has.
    @Published private(set) var cities: [City] = []
    @Published private(set) var countries: [Country] = []
    @Published private(set) var placeCounts: [String: Int] = [:]
    /// The city Discover is scoped to (persisted).
    @Published private(set) var selectedCityId: String?
    var selectedCity: City? { cities.first { $0.id == selectedCityId } }
    private static let cityKey = "sp_selected_city"
    @Published var placeStatuses: [String: PlaceUserStatus] = [:]

    init(preview: Bool = false) {
        let auth = AuthStore()
        let client = SupabaseClient(sessionProvider: auth.tokens)
        let analytics = ConsoleAnalytics()

        self.auth = auth
        self.client = client
        self.analytics = analytics

        // On a 401, refresh the token (or fall back to anon) and retry once.
        client.onUnauthorized = { [weak auth] in await auth?.refreshSession() ?? false }

        self.places = SupabasePlaceRepository(client: client)
        self.geo = SupabaseGeoRepository(client: client)
        self.categoriesRepo = SupabaseCategoryRepository(client: client)
        self.collections = SupabaseCollectionsRepository(client: client)
        self.search = SupabaseSearchService(client: client)
        self.saved = SupabaseSavedPlacesRepository(client: client, session: auth.tokens)
        self.ratings = SupabaseRatingsRepository(client: client, session: auth.tokens)
        self.reports = SupabaseReportsRepository(client: client, session: auth.tokens)
        self.events = SupabaseEventsRepository(client: client)
        self.routes = SupabaseRoutesRepository(client: client)

        let entitlements = SupabaseEntitlementService(client: client, session: auth.tokens)
        self.entitlements = entitlements
        self.purchases = PurchaseService(client: client, auth: auth, entitlements: entitlements, analytics: analytics)
        self.location = LocationService()
    }

    func bootstrap() async {
        // Skip network work when the app is only hosting a unit-test bundle.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        analytics.track(.appOpen)
        if let cats = try? await categoriesRepo.categories() { categories = cats }
        await loadGeo()
        await entitlements.refresh()
        await refreshUserState()
    }

    func refreshUserState() async {
        guard auth.isSignedIn else { savedIds = []; placeStatuses = [:]; return }
        if let ids = try? await saved.savedIds() { savedIds = ids }
        if let st = try? await saved.statuses() { placeStatuses = st }
    }

    // MARK: City selection

    /// Loads the city list and picks the Discover city: the saved one, else the nearest
    /// (only if location is already allowed — never prompts on launch), else Kyiv.
    func loadGeo() async {
        async let c = geo.cities()
        async let k = geo.countries()
        async let counts = places.cityCounts()
        guard let all = try? await c else { return }
        countries = (try? await k) ?? []
        placeCounts = (try? await counts) ?? [:]
        cities = all.filter { (placeCounts[$0.id] ?? 0) > 0 }
        if let saved = UserDefaults.standard.string(forKey: Self.cityKey), cities.contains(where: { $0.id == saved }) {
            selectedCityId = saved
        } else if let here = await location.requestLocation(), let near = nearestCity(to: here) {
            selectCity(near.id)
        } else {
            selectedCityId = (cities.first { $0.slug == "kyiv" } ?? cities.first)?.id
        }
    }

    func selectCity(_ id: String) {
        selectedCityId = id
        UserDefaults.standard.set(id, forKey: Self.cityKey)
    }

    /// Asks for location if needed, then switches to the nearest covered city.
    /// Returns false when there's no permission or no city within reach.
    @discardableResult
    func selectNearestCity() async -> Bool {
        if location.authorization == .notDetermined {
            location.requestPermission()
            for _ in 0..<40 where location.authorization == .notDetermined { try? await Task.sleep(for: .milliseconds(250)) }
        }
        guard let here = await location.requestLocation(), let near = nearestCity(to: here) else { return false }
        selectCity(near.id)
        return true
    }

    private func nearestCity(to c: CLLocationCoordinate2D, withinKm: Double = 80) -> City? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return cities
            .compactMap { city -> (City, Double)? in
                guard let la = city.lat, let ln = city.lng else { return nil }
                return (city, here.distance(from: CLLocation(latitude: la, longitude: ln)))
            }
            .filter { $0.1 <= withinKm * 1000 }
            .min { $0.1 < $1.1 }?.0
    }

    func country(for id: String?) -> Country? { countries.first { $0.id == id } }

    func isUnlocked(_ placeId: String) async -> Bool { await entitlements.isUnlocked(placeId: placeId) }

    func category(for id: String?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    // Saved toggles with optimistic UI.
    func toggleSaved(_ placeId: String) async {
        if savedIds.contains(placeId) {
            savedIds.remove(placeId)
            try? await saved.unsave(placeId: placeId)
        } else {
            savedIds.insert(placeId)
            analytics.track(.placeSaved(placeId: placeId))
            try? await saved.save(placeId: placeId)
        }
    }

    /// Persist onboarding interests (used to rank Discover — never to hide content).
    func saveInterests(_ interests: [String]) async {
        guard let uid = auth.currentUserId else { return }
        struct Body: Encodable { let id: String; let interests: [String]; let onboarded: Bool }
        struct Row: Decodable { let id: String? }
        _ = try? await client.insert("profiles", body: [Body(id: uid, interests: interests, onboarded: true)], as: [Row].self, upsert: true)
    }

    /// Full account + data deletion via the delete-account Edge Function (service role).
    func deleteAccount() async throws {
        struct Empty: Encodable {}
        struct Resp: Decodable { let deleted: Bool? }
        _ = try await client.callFunction("delete-account", body: Empty(), as: Resp.self)
        auth.signOut()
        entitlements.clear()
        await DiskCache.shared.clearAll()
        savedIds = []; placeStatuses = [:]
    }

    func setStatus(_ placeId: String, _ status: PlaceUserStatus?) async {
        if let status { placeStatuses[placeId] = status } else { placeStatuses[placeId] = nil }
        if status == .visited { analytics.track(.placeVisited(placeId: placeId)) }
        try? await saved.setStatus(placeId: placeId, status: status)
    }
}

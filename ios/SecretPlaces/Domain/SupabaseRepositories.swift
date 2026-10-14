import Foundation

private func q(_ name: String, _ value: String) -> URLQueryItem { URLQueryItem(name: name, value: value) }

// MARK: - Places

final class SupabasePlaceRepository: PlaceRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func list(_ query: PlaceQuery) async throws -> [PlaceTeaser] {
        var items: [URLQueryItem] = [q("select", "*")]
        if let c = query.cityId { items.append(q("city_id", "eq.\(c)")) }
        if let n = query.neighborhoodId { items.append(q("neighborhood_id", "eq.\(n)")) }
        if let c = query.countryId { items.append(q("country_id", "eq.\(c)")) }
        if let cat = query.categoryId { items.append(q("primary_category_id", "eq.\(cat)")) }
        if let a = query.accessType { items.append(q("access_type", "eq.\(a.rawValue)")) }
        if query.freeOnly { items.append(q("is_free_now", "eq.true")) }
        if query.featuredOnly { items.append(q("featured", "eq.true")) }
        if query.editorsOnly { items.append(q("editors_choice", "eq.true")) }
        items.append(q("order", query.orderNewest ? "created_at.desc" : "featured.desc,rating.desc"))
        items.append(q("limit", String(query.limit)))
        return try await client.select("places_public", query: items, as: [PlaceTeaser].self)
    }

    func byIds(_ ids: [String]) async throws -> [PlaceTeaser] {
        guard !ids.isEmpty else { return [] }
        let list = ids.joined(separator: ",")
        return try await client.select("places_public", query: [q("select", "*"), q("id", "in.(\(list))")], as: [PlaceTeaser].self)
    }

    func details(id: String) async throws -> PlaceDetails {
        try await client.rpc("get_place_details", params: ["p_place_id": AnyEncodable(id)], as: PlaceDetails.self)
    }

    func cityCounts() async throws -> [String: Int] {
        struct Row: Decodable { let cityId: String? }
        let rows = try await client.select("places_public", query: [q("select", "city_id"), q("limit", "10000")], as: [Row].self)
        return rows.reduce(into: [:]) { acc, r in if let c = r.cityId { acc[c, default: 0] += 1 } }
    }

    func nearby(lat: Double, lng: Double, radiusM: Double, limit: Int) async throws -> [NearbyPlace] {
        try await client.rpc("nearby_places", params: [
            "p_lat": AnyEncodable(lat), "p_lng": AnyEncodable(lng),
            "p_radius_m": AnyEncodable(radiusM), "p_limit": AnyEncodable(limit),
        ], as: [NearbyPlace].self)
    }
}

// MARK: - Geo

final class SupabaseGeoRepository: GeoRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func countries() async throws -> [Country] {
        try await client.select("countries", query: [q("select", "*"), q("order", "name.asc")], as: [Country].self)
    }
    func cities() async throws -> [City] {
        try await client.select("cities", query: [q("select", "*"), q("order", "title.asc")], as: [City].self)
    }
    func neighborhoods(cityId: String) async throws -> [Neighborhood] {
        try await client.select("neighborhoods", query: [q("select", "*"), q("city_id", "eq.\(cityId)"), q("order", "title.asc")], as: [Neighborhood].self)
    }
}

// MARK: - Categories

final class SupabaseCategoryRepository: CategoryRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    func categories() async throws -> [Category] {
        try await client.select("categories", query: [q("select", "*"), q("is_active", "eq.true"), q("order", "sort.asc")], as: [Category].self)
    }
}

// MARK: - Collections

final class SupabaseCollectionsRepository: CollectionsRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func collections() async throws -> [PlaceCollection] {
        try await client.select("collections", query: [q("select", "*"), q("status", "eq.published"), q("order", "featured.desc")], as: [PlaceCollection].self)
    }
    func places(collectionId: String) async throws -> [PlaceTeaser] {
        // collection_places → place ids, then places_public.
        struct Row: Decodable { let placeId: String }
        let rows = try await client.select("collection_places", query: [q("select", "place_id"), q("collection_id", "eq.\(collectionId)"), q("order", "sort.asc")], as: [Row].self)
        guard !rows.isEmpty else { return [] }
        let ids = rows.map { $0.placeId }.joined(separator: ",")
        return try await client.select("places_public", query: [q("select", "*"), q("id", "in.(\(ids))")], as: [PlaceTeaser].self)
    }
}

// MARK: - Search

final class SupabaseSearchService: SearchService {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func search(_ text: String) async throws -> SearchResults {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return SearchResults() }
        let like = "*\(term)*"
        async let places = client.select("places_public",
            query: [q("select", "*"), q("or", "(teaser_title.ilike.\(like),teaser_description.ilike.\(like))"), q("limit", "40")],
            as: [PlaceTeaser].self)
        async let cities = client.select("cities",
            query: [q("select", "*"), q("title", "ilike.\(like)"), q("limit", "10")], as: [City].self)
        async let hoods = client.select("neighborhoods",
            query: [q("select", "*"), q("title", "ilike.\(like)"), q("limit", "10")], as: [Neighborhood].self)
        return try await SearchResults(places: places, cities: cities, neighborhoods: hoods)
    }
}

// MARK: - Saved places / status (authenticated)

final class SupabaseSavedPlacesRepository: SavedPlacesRepository {
    private let client: SupabaseClient
    private let session: TokenHolder
    init(client: SupabaseClient, session: TokenHolder) { self.client = client; self.session = session }

    private func requireUser() throws -> String {
        guard let uid = session.userId else { throw AppError.notAuthenticated }
        return uid
    }

    func savedIds() async throws -> Set<String> {
        guard session.isSignedIn else { return [] }
        struct Row: Decodable { let placeId: String }
        let rows = try await client.select("user_saved_places", query: [q("select", "place_id")], as: [Row].self)
        return Set(rows.map { $0.placeId })
    }

    func save(placeId: String) async throws {
        let uid = try requireUser()
        struct Body: Encodable { let userId: String; let placeId: String }
        _ = try await client.insert("user_saved_places", body: [Body(userId: uid, placeId: placeId)], as: [SavedRow].self, upsert: true)
    }

    func unsave(placeId: String) async throws {
        _ = try requireUser()
        try await client.delete("user_saved_places", query: [q("place_id", "eq.\(placeId)")])
    }

    func statuses() async throws -> [String: PlaceUserStatus] {
        guard session.isSignedIn else { return [:] }
        struct Row: Decodable { let placeId: String; let status: PlaceUserStatus }
        let rows = try await client.select("user_place_status", query: [q("select", "place_id,status")], as: [Row].self)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.placeId, $0.status) })
    }

    func setStatus(placeId: String, status: PlaceUserStatus?) async throws {
        let uid = try requireUser()
        if let status {
            struct Body: Encodable { let userId: String; let placeId: String; let status: String }
            _ = try await client.insert("user_place_status", body: [Body(userId: uid, placeId: placeId, status: status.rawValue)], as: [SavedRow].self, upsert: true)
        } else {
            try await client.delete("user_place_status", query: [q("place_id", "eq.\(placeId)")])
        }
    }

    private struct SavedRow: Decodable { let placeId: String? }
}

// MARK: - Ratings / Reports

final class SupabaseRatingsRepository: RatingsRepository {
    private let client: SupabaseClient
    private let session: TokenHolder
    init(client: SupabaseClient, session: TokenHolder) { self.client = client; self.session = session }
    func rate(placeId: String, score: Int, feedback: String?) async throws {
        guard let uid = session.userId else { throw AppError.notAuthenticated }
        struct Body: Encodable { let userId: String; let placeId: String; let score: Int; let feedback: String? }
        struct Row: Decodable { let id: String? }
        _ = try await client.insert("ratings", body: [Body(userId: uid, placeId: placeId, score: score, feedback: feedback)], as: [Row].self, upsert: true)
    }
}

final class SupabaseReportsRepository: ReportsRepository {
    private let client: SupabaseClient
    private let session: TokenHolder
    init(client: SupabaseClient, session: TokenHolder) { self.client = client; self.session = session }
    func report(placeId: String, reason: String, details: String?) async throws {
        struct Body: Encodable { let userId: String?; let placeId: String; let reason: String; let details: String? }
        struct Row: Decodable { let id: String? }
        _ = try await client.insert("reports", body: [Body(userId: session.userId, placeId: placeId, reason: reason, details: details)], as: [Row].self)
    }
}

// MARK: - Events

final class SupabaseEventsRepository: EventsRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    func upcoming(cityId: String?, limit: Int) async throws -> [EventItem] {
        var items: [URLQueryItem] = [q("select", "*"), q("order", "starts_at.asc"), q("limit", String(limit))]
        if let c = cityId { items.append(q("city_id", "eq.\(c)")) }
        return try await client.select("events_public", query: items, as: [EventItem].self)
    }
}

// MARK: - Routes (bar crawls)

final class SupabaseRoutesRepository: RoutesRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    func list(cityId: String?) async throws -> [RouteSummary] {
        var items: [URLQueryItem] = [q("select", "*"), q("order", "featured.desc,title.asc")]
        if let c = cityId { items.append(q("city_id", "eq.\(c)")) }
        return try await client.select("routes_public", query: items, as: [RouteSummary].self)
    }
    func details(slug: String) async throws -> RouteDetails {
        try await client.rpc("get_route_details", params: ["p_slug": AnyEncodable(slug)], as: RouteDetails.self)
    }
}

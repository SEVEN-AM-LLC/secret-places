import Foundation

/// Query for listing teaser places.
struct PlaceQuery: Equatable {
    var cityId: String?
    var neighborhoodId: String?
    var countryId: String?
    var categoryId: String?
    var accessType: AccessType?
    var freeOnly: Bool = false
    var featuredOnly: Bool = false
    var editorsOnly: Bool = false
    var limit: Int = 50
    var orderNewest: Bool = false
}

struct SearchResults: Equatable {
    var places: [PlaceTeaser] = []
    var cities: [City] = []
    var neighborhoods: [Neighborhood] = []
    var isEmpty: Bool { places.isEmpty && cities.isEmpty && neighborhoods.isEmpty }
}

protocol PlaceRepository: Sendable {
    func list(_ query: PlaceQuery) async throws -> [PlaceTeaser]
    func byIds(_ ids: [String]) async throws -> [PlaceTeaser]
    func details(id: String) async throws -> PlaceDetails
    func nearby(lat: Double, lng: Double, radiusM: Double, limit: Int) async throws -> [NearbyPlace]
    /// Published places per city id.
    func cityCounts() async throws -> [String: Int]
}

protocol GeoRepository: Sendable {
    func countries() async throws -> [Country]
    func cities() async throws -> [City]
    func neighborhoods(cityId: String) async throws -> [Neighborhood]
}

protocol CategoryRepository: Sendable {
    func categories() async throws -> [Category]
}

protocol CollectionsRepository: Sendable {
    func collections() async throws -> [PlaceCollection]
    func places(collectionId: String) async throws -> [PlaceTeaser]
}

protocol SearchService: Sendable {
    func search(_ text: String) async throws -> SearchResults
}

protocol SavedPlacesRepository: Sendable {
    func savedIds() async throws -> Set<String>
    func save(placeId: String) async throws
    func unsave(placeId: String) async throws
    func statuses() async throws -> [String: PlaceUserStatus]
    func setStatus(placeId: String, status: PlaceUserStatus?) async throws
}

protocol EntitlementService: AnyObject, Sendable {
    func unlockedPlaceIds() async throws -> Set<String>
    func isUnlocked(placeId: String) async -> Bool
    func refresh() async
}

protocol RatingsRepository: Sendable {
    func rate(placeId: String, score: Int, feedback: String?) async throws
}

protocol ReportsRepository: Sendable {
    func report(placeId: String, reason: String, details: String?) async throws
}

protocol EventsRepository: Sendable {
    func upcoming(cityId: String?, limit: Int) async throws -> [EventItem]
}

protocol RoutesRepository: Sendable {
    func list(cityId: String?) async throws -> [RouteSummary]
    func details(slug: String) async throws -> RouteDetails
}

import Foundation
import CoreLocation

enum AccessType: String, Codable, Equatable, Sendable {
    case free, paid
    case includedInCollection
    case promotionalFree

    var isPayable: Bool { self == .paid }
}

struct Category: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let icon: String?
    let sort: Int
}

struct Country: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let name: String
    let emojiFlag: String?
    let coverUrl: String?
}

struct City: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let lat: Double?
    let lng: Double?
    let coverUrl: String?
    let countryId: String?
    let isOutsideCity: Bool?
}

struct Neighborhood: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let cityId: String
    let slug: String
    let title: String
    let description: String?
    let lat: Double?
    let lng: Double?
    let coverUrl: String?
}

struct PlaceCollection: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let coverUrl: String?
    let isFree: Bool
    let priceCents: Int
    let featured: Bool
    let cityId: String?
}

struct PlaceImage: Codable, Equatable, Sendable {
    let url: String
    let sort: Int?
    let isHero: Bool?
}

/// The public teaser card — what everyone can see (from `places_public`).
struct PlaceTeaser: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let teaserTitle: String
    let teaserDescription: String
    let heroImageUrl: String?
    let approxLat: Double?
    let approxLng: Double?
    let countryId: String?
    let regionId: String?
    let cityId: String?
    let neighborhoodId: String?
    let primaryCategoryId: String?
    let accessType: AccessType
    let priceCents: Int
    let currency: String
    let productId: String?
    let isFreeNow: Bool?
    let travelTimeMin: Int?
    let recommendedTransport: String?
    let bestTime: String?
    let bestSeason: String?
    let expectedDurationMin: Int?
    let crowdLevel: String?
    let priceLevel: Int?
    let accessibilityInfo: String?
    let safetyInfo: String?
    let mobileSignal: String?
    let whatToBring: String?
    let rating: Double
    let ratingsCount: Int
    let featured: Bool
    let editorsChoice: Bool

    var isFreeExperience: Bool { accessType == .free || accessType == .promotionalFree || (isFreeNow ?? false) }
    var approxCoordinate: CLLocationCoordinate2D? {
        guard let la = approxLat, let ln = approxLng else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: ln)
    }
    var priceLabel: String {
        if isFreeExperience { return String(localized: "Free") }
        // No product of its own → sold through the city pass, not for this price alone.
        if productId == nil { return String(localized: "City pass") }
        return String(format: "$%.2f", Double(priceCents) / 100.0)
    }
}

/// Full details from `get_place_details` RPC. Sensitive fields are present ONLY when unlocked.
struct PlaceDetails: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let locked: Bool
    let teaserTitle: String
    let teaserDescription: String
    let heroImageUrl: String?
    let approxLat: Double?
    let approxLng: Double?
    let cityId: String?
    let neighborhoodId: String?
    let primaryCategoryId: String?
    let accessType: AccessType
    let priceCents: Int
    let currency: String
    let productId: String?
    let isFreeNow: Bool?
    let travelTimeMin: Int?
    let recommendedTransport: String?
    let bestTime: String?
    let bestSeason: String?
    let expectedDurationMin: Int?
    let crowdLevel: String?
    let priceLevel: Int?
    let accessibilityInfo: String?
    let safetyInfo: String?
    let mobileSignal: String?
    let whatToBring: String?
    let rating: Double
    let ratingsCount: Int
    let featured: Bool
    let editorsChoice: Bool
    let images: [PlaceImage]
    let tags: [String]
    let hasEntryPassword: Bool?

    // SENSITIVE — only when unlocked
    let fullTitle: String?
    let fullDescription: String?
    let exactLat: Double?
    let exactLng: Double?
    let exactAddress: String?
    let businessName: String?
    let walkingInstructions: String?
    let parkingInfo: String?
    let insiderTips: String?
    let photoSpot: String?
    let website: String?
    let bookingUrl: String?
    let entryPassword: String?
    let entryNote: String?
    let appleMapsUrl: String?
    let googleMapsUrl: String?
    /// "city" when this place is sold through its city's pass (productId is then the pass).
    let unlockScope: String?
    let cityTitle: String?

    var isUnlocked: Bool { !locked }
    var unlocksWithCityPass: Bool { unlockScope == "city" }
    var requiresPassword: Bool { hasEntryPassword ?? false }
    var exactCoordinate: CLLocationCoordinate2D? {
        guard let la = exactLat, let ln = exactLng else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: ln)
    }
    var approxCoordinate: CLLocationCoordinate2D? {
        guard let la = approxLat, let ln = approxLng else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: ln)
    }
    var priceLabel: String {
        if accessType == .free || (isFreeNow ?? false) { return String(localized: "Free") }
        return String(format: "$%.2f", Double(priceCents) / 100.0)
    }
    var displayTitle: String { isUnlocked ? (fullTitle ?? teaserTitle) : teaserTitle }
}

/// A nearby result (from nearby_places RPC).
struct NearbyPlace: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let teaserTitle: String
    let teaserDescription: String
    let heroImageUrl: String?
    let approxLat: Double?
    let approxLng: Double?
    let primaryCategoryId: String?
    let accessType: AccessType
    let priceCents: Int
    let currency: String
    let isFreeNow: Bool
    let rating: Double
    let ratingsCount: Int
    let distanceM: Double
    let unlocked: Bool

    var distanceLabel: String {
        if distanceM < 1000 { return "\(Int(distanceM)) m" }
        return String(format: "%.1f km", distanceM / 1000)
    }
}

enum PlaceUserStatus: String, Codable, Sendable { case wantToVisit = "want_to_visit", visited }

// MARK: - Events

struct EventItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let kind: String
    let startsAt: Date
    let endsAt: Date?
    let posterUrl: String?
    let ticketUrl: String?
    let priceFromCents: Int?
    let currency: String
    let isFree: Bool
    let lineup: [String]
    let featured: Bool
    let cityId: String?
    let placeId: String?
    let venueTeaser: String?
    let venueApproxLat: Double?
    let venueApproxLng: Double?
    let venueCategory: String?
    let venueAccess: AccessType?

    var priceLabel: String {
        if isFree { return String(localized: "Free") }
        if let c = priceFromCents { return String(localized: "from \(c/100) \(currency)") }
        return String(localized: "Ticketed")
    }
}

// MARK: - Routes (bar crawls)

struct RouteSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let summary: String?
    let cityId: String?
    let kind: String
    let coverUrl: String?
    let isFree: Bool
    let priceCents: Int
    let currency: String
    let productId: String?
    let distanceM: Int?
    let durationMin: Int?
    let featured: Bool
    let stopCount: Int

    var priceLabel: String { isFree ? String(localized: "Free") : String(format: "$%.2f", Double(priceCents) / 100.0) }
}

struct RouteStop: Codable, Equatable, Sendable {
    let position: Int
    let note: String?
    let id: String
    let slug: String
    let teaserTitle: String
    let teaserDescription: String
    let approxLat: Double?
    let approxLng: Double?
    let primaryCategoryId: String?
    let locked: Bool
    let hasEntryPassword: Bool?
    let fullTitle: String?
    let exactLat: Double?
    let exactLng: Double?
    let businessName: String?
    let entryPassword: String?
    let entryNote: String?

    var requiresPassword: Bool { hasEntryPassword ?? false }
    var displayTitle: String { locked ? teaserTitle : (fullTitle ?? teaserTitle) }
    var exactCoordinate: CLLocationCoordinate2D? {
        guard let la = exactLat, let ln = exactLng else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: ln)
    }
}

struct RouteDetails: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let summary: String?
    let description: String?
    let kind: String
    let cityId: String?
    let coverUrl: String?
    let isFree: Bool
    let priceCents: Int
    let currency: String
    let productId: String?
    let distanceM: Int?
    let durationMin: Int?
    let featured: Bool
    let owned: Bool
    let stops: [RouteStop]

    var priceLabel: String { isFree ? String(localized: "Free") : String(format: "$%.2f", Double(priceCents) / 100.0) }
}

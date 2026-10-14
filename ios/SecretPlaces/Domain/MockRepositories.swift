import Foundation

/// In-memory repository for previews, offline demo and tests. It ENFORCES the
/// same privacy rule as the backend: `details(id:)` returns a locked teaser
/// (no sensitive fields) unless the place is free/promo or in `unlockedIds`.
final class MockPlaceRepository: PlaceRepository, @unchecked Sendable {
    private var teasers: [PlaceTeaser]
    private var sensitive: [String: (fullTitle: String, fullDesc: String, lat: Double, lng: Double, business: String)]
    var unlockedIds: Set<String>

    init(teasers: [PlaceTeaser] = MockData.teasers,
         sensitive: [String: (fullTitle: String, fullDesc: String, lat: Double, lng: Double, business: String)] = MockData.sensitive,
         unlockedIds: Set<String> = []) {
        self.teasers = teasers
        self.sensitive = sensitive
        self.unlockedIds = unlockedIds
    }

    func list(_ query: PlaceQuery) async throws -> [PlaceTeaser] {
        teasers.filter { p in
            if let c = query.cityId, p.cityId != c { return false }
            if let n = query.neighborhoodId, p.neighborhoodId != n { return false }
            if let cat = query.categoryId, p.primaryCategoryId != cat { return false }
            if let a = query.accessType, p.accessType != a { return false }
            if query.freeOnly && !p.isFreeExperience { return false }
            if query.featuredOnly && !p.featured { return false }
            if query.editorsOnly && !p.editorsChoice { return false }
            return true
        }
    }

    func byIds(_ ids: [String]) async throws -> [PlaceTeaser] { teasers.filter { ids.contains($0.id) } }

    func details(id: String) async throws -> PlaceDetails {
        guard let t = teasers.first(where: { $0.id == id }) else { throw AppError.notFound }
        let unlocked = t.isFreeExperience || unlockedIds.contains(id)
        let s = sensitive[id]
        return PlaceDetails(
            id: t.id, slug: t.slug, locked: !unlocked, teaserTitle: t.teaserTitle, teaserDescription: t.teaserDescription,
            heroImageUrl: t.heroImageUrl, approxLat: t.approxLat, approxLng: t.approxLng,
            cityId: t.cityId, neighborhoodId: t.neighborhoodId, primaryCategoryId: t.primaryCategoryId,
            accessType: t.accessType, priceCents: t.priceCents, currency: t.currency, productId: t.productId,
            isFreeNow: t.isFreeNow, travelTimeMin: t.travelTimeMin, recommendedTransport: t.recommendedTransport,
            bestTime: t.bestTime, bestSeason: t.bestSeason, expectedDurationMin: t.expectedDurationMin,
            crowdLevel: t.crowdLevel, priceLevel: t.priceLevel, accessibilityInfo: t.accessibilityInfo,
            safetyInfo: t.safetyInfo, mobileSignal: t.mobileSignal, whatToBring: t.whatToBring,
            rating: t.rating, ratingsCount: t.ratingsCount, featured: t.featured, editorsChoice: t.editorsChoice,
            images: [], tags: unlocked ? ["hidden","local"] : [], hasEntryPassword: true,
            // SENSITIVE — present ONLY when unlocked (mirrors the server)
            fullTitle: unlocked ? s?.fullTitle : nil,
            fullDescription: unlocked ? s?.fullDesc : nil,
            exactLat: unlocked ? s?.lat : nil,
            exactLng: unlocked ? s?.lng : nil,
            exactAddress: unlocked ? "Kyiv, Ukraine" : nil,
            businessName: unlocked ? s?.business : nil,
            walkingInstructions: unlocked ? "Through the arch, keep left." : nil,
            parkingInfo: nil, insiderTips: unlocked ? "Go early." : nil, photoSpot: nil,
            website: nil, bookingUrl: nil,
            entryPassword: unlocked ? "the gate is the sign" : nil,
            entryNote: unlocked ? "Face control at the gate." : nil,
            appleMapsUrl: nil, googleMapsUrl: nil, unlockScope: "place", cityTitle: nil)
    }

    func cityCounts() async throws -> [String: Int] {
        teasers.reduce(into: [:]) { acc, t in if let c = t.cityId { acc[c, default: 0] += 1 } }
    }

    func nearby(lat: Double, lng: Double, radiusM: Double, limit: Int) async throws -> [NearbyPlace] {
        teasers.compactMap { t in
            guard let la = t.approxLat, let ln = t.approxLng else { return nil }
            let d = Geo.distanceMeters(lat, lng, la, ln)
            guard d <= radiusM else { return nil }
            return NearbyPlace(id: t.id, slug: t.slug, teaserTitle: t.teaserTitle, teaserDescription: t.teaserDescription,
                heroImageUrl: t.heroImageUrl, approxLat: la, approxLng: ln, primaryCategoryId: t.primaryCategoryId,
                accessType: t.accessType, priceCents: t.priceCents, currency: t.currency, isFreeNow: t.isFreeExperience,
                rating: t.rating, ratingsCount: t.ratingsCount, distanceM: d, unlocked: t.isFreeExperience || unlockedIds.contains(t.id))
        }.sorted { $0.distanceM < $1.distanceM }.prefix(limit).map { $0 }
    }
}

enum MockData {
    static func teaser(_ id: String, _ title: String, access: AccessType, city: String = "kyiv-id", hood: String = "gg-id",
                       cat: String = "bars-id", featured: Bool = false, editors: Bool = false,
                       lat: Double = 50.45, lng: Double = 30.52) -> PlaceTeaser {
        PlaceTeaser(id: id, slug: id, teaserTitle: title, teaserDescription: "A hidden spot.", heroImageUrl: nil,
            approxLat: lat, approxLng: lng, countryId: "ua", regionId: nil, cityId: city, neighborhoodId: hood,
            primaryCategoryId: cat, accessType: access, priceCents: access == .free ? 0 : 99, currency: "USD",
            productId: access == .paid ? "com.secretplaces.place.\(id)" : nil, isFreeNow: access == .promotionalFree ? true : nil,
            travelTimeMin: 12, recommendedTransport: "walk", bestTime: "evening", bestSeason: "all year",
            expectedDurationMin: 60, crowdLevel: "medium", priceLevel: 2, accessibilityInfo: nil, safetyInfo: nil,
            mobileSignal: "good", whatToBring: nil, rating: 4.5, ratingsCount: 12, featured: featured, editorsChoice: editors)
    }

    static let teasers: [PlaceTeaser] = [
        teaser("free1", "Hidden coffee courtyard", access: .free, cat: "coffee-id", featured: true, lat: 50.4487, lng: 30.5142),
        teaser("paid1", "Unmarked cocktail bar", access: .paid, editors: true, lat: 50.4490, lng: 30.5150),
        teaser("paid2", "Rooftop date view", access: .paid, featured: true, lat: 50.4483, lng: 30.5133),
        teaser("promo1", "Wine cellar — free this week", access: .promotionalFree, lat: 50.4481, lng: 30.5147),
    ]

    static let sensitive: [String: (fullTitle: String, fullDesc: String, lat: Double, lng: Double, business: String)] = [
        "free1": ("Courtyard Roasters", "Best espresso in the district.", 50.4487, 30.5142, "Courtyard Roasters"),
        "paid1": ("The Val Speakeasy", "Knock-to-enter speakeasy.", 50.4490, 30.5150, "The Val"),
        "paid2": ("Val Rooftop", "Sunset over old Kyiv.", 50.4483, 30.5133, "Val Rooftop"),
        "promo1": ("Pidval Wine", "Candlelit natural-wine cellar.", 50.4481, 30.5147, "Pidval Wine"),
    ]
}

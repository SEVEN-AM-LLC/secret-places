import Foundation

/// Analytics events. Never carries exact/sensitive GPS — only coarse context.
enum AnalyticsEvent: Equatable {
    case appOpen
    case discoverView
    case cityView(citySlug: String)
    case neighborhoodView(slug: String)
    case placePreview(placeId: String, locked: Bool)
    case placeUnlockStarted(placeId: String)
    case placeUnlockSuccess(placeId: String)
    case placeUnlockFailed(placeId: String, reason: String)
    case freePlaceOpened(placeId: String)
    case placeSaved(placeId: String)
    case placeVisited(placeId: String)
    case mapOpened
    case searchPerformed(queryLength: Int)   // never the raw query
    case collectionOpened(slug: String)
    case shareStarted(kind: String)
    case locationPermissionResult(granted: Bool)
    case suggestPlace

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .discoverView: return "discover_view"
        case .cityView: return "city_view"
        case .neighborhoodView: return "neighborhood_view"
        case .placePreview: return "place_preview"
        case .placeUnlockStarted: return "place_unlock_started"
        case .placeUnlockSuccess: return "place_unlock_success"
        case .placeUnlockFailed: return "place_unlock_failed"
        case .freePlaceOpened: return "free_place_opened"
        case .placeSaved: return "place_saved"
        case .placeVisited: return "place_visited"
        case .mapOpened: return "map_opened"
        case .searchPerformed: return "search_performed"
        case .collectionOpened: return "collection_opened"
        case .shareStarted: return "share_started"
        case .locationPermissionResult: return "location_permission_result"
        case .suggestPlace: return "suggest_place"
        }
    }
}

protocol AnalyticsService: Sendable {
    func track(_ event: AnalyticsEvent)
}

/// Console analytics — a lightweight abstraction; swap for a real provider later.
/// Deliberately records only coarse, non-identifying parameters.
final class ConsoleAnalytics: AnalyticsService {
    private let enabled: @Sendable () -> Bool
    init(enabled: @escaping @Sendable () -> Bool = { true }) { self.enabled = enabled }
    func track(_ event: AnalyticsEvent) {
        guard enabled() else { return }
        #if DEBUG
        print("📊 analytics:", event.name)
        #endif
    }
}

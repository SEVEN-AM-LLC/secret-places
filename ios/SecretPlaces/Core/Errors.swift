import Foundation

/// Typed errors surfaced across the app.
enum AppError: Error, Equatable, LocalizedError {
    case notAuthenticated
    case network(String)
    case decoding(String)
    case server(status: Int, message: String)
    case notFound
    case purchaseFailed(String)
    case purchaseCancelled
    case purchasePending
    case entitlementMissing
    case offline
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return String(localized: "You need to sign in to do that.")
        case .network(let m): return String(localized: "Network problem: \(m)")
        case .decoding(let m): return String(localized: "Could not read the data: \(m)")
        case .server(let s, let m): return String(localized: "Server error (\(s)): \(m)")
        case .notFound: return String(localized: "Not found.")
        case .purchaseFailed(let m): return String(localized: "Purchase failed: \(m)")
        case .purchaseCancelled: return String(localized: "Purchase cancelled.")
        case .purchasePending: return String(localized: "Purchase is pending approval.")
        case .entitlementMissing: return String(localized: "This place isn't unlocked yet.")
        case .offline: return String(localized: "You're offline.")
        case .unknown(let m): return m
        }
    }
}

import Foundation
import CoreLocation

@MainActor
protocol LocationServing: AnyObject {
    var authorization: CLAuthorizationStatus { get }
    var lastCoordinate: CLLocationCoordinate2D? { get }
    func requestPermission()
    func requestLocation() async -> CLLocationCoordinate2D?
}

/// CoreLocation wrapper. Location is OPTIONAL — the app is fully usable without it
/// (manual city selection). Only requests when-in-use authorization.
@MainActor
final class LocationService: NSObject, ObservableObject, LocationServing, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    var onPermissionResult: ((Bool) -> Void)?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func requestLocation() async -> CLLocationCoordinate2D? {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { return nil }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            let granted = status == .authorizedWhenInUse || status == .authorizedAlways
            if status != .notDetermined { self.onPermissionResult?(granted) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            if let coord { self.lastCoordinate = coord }
            self.continuation?.resume(returning: coord)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}

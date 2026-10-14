import SwiftUI
import MapKit

/// A real Apple Maps snapshot of a place's APPROXIMATE area — the honest stand-in
/// when we have no photo of the place itself, or must not show one yet (locked
/// paid places: a venue photo + rough area is reverse-image-searchable).
/// Uses only the public approx coordinates, with POI labels stripped, so it
/// reveals nothing the teaser doesn't already.
struct AreaMapImage: View {
    let coordinate: CLLocationCoordinate2D?
    var height: CGFloat = 150
    var locked: Bool = false
    /// Edge length of the shown region; widen it to fit several stops.
    var spanMeters: CLLocationDistance = 1600
    /// Off for overview maps (e.g. a whole city) where a "somewhere here" zone makes no sense.
    var showsMarker: Bool = true

    @State private var snapshot: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill().transition(.opacity)
                }
                LinearGradient(colors: [.clear, Theme.bg.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                if coordinate != nil { if showsMarker { zoneMarker(diameter: min(geo.size.width, height) * 0.55) } }
                else { Image(systemName: "map").font(.title2).foregroundStyle(Theme.textMuted.opacity(0.55)) }
            }
            .frame(width: geo.size.width, height: height)
            .clipped()
            .task(id: TaskKey(coordinate: coordinate, width: geo.size.width)) {
                await load(width: geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityLabel(Text(locked ? "Map of the approximate area" : "Map of the area"))
    }

    /// A soft "somewhere in here" zone rather than a pin — the coords are approximate.
    private func zoneMarker(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.16))
            Circle().strokeBorder(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            Image(systemName: locked ? "lock.fill" : "location.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.bg)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .frame(width: diameter, height: diameter)
    }

    private struct TaskKey: Equatable {
        let lat: Double?, lng: Double?, width: Int
        init(coordinate: CLLocationCoordinate2D?, width: CGFloat) {
            lat = coordinate?.latitude; lng = coordinate?.longitude; self.width = Int(width)
        }
    }

    private func load(width: CGFloat) async {
        guard let coordinate, width > 1 else { return }
        let size = CGSize(width: width, height: height)
        let key = MapSnapshotCache.key(coordinate, size, displayScale, spanMeters)
        if let cached = MapSnapshotCache.shared.object(forKey: key) { snapshot = cached; return }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
        options.size = size
        options.scale = displayScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = true
        // Map tiles can fail transiently (MKError.serverFailure / throttling) — retry once.
        var image: UIImage?
        for attempt in 0..<2 where image == nil && !Task.isCancelled {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1.5)) }
            image = try? await MKMapSnapshotter(options: options).start().image
        }
        guard let image else { return }
        MapSnapshotCache.shared.setObject(image, forKey: key)
        withAnimation(.easeOut(duration: 0.25)) { snapshot = image }
    }
}

/// Snapshots are relatively expensive; keep recent ones in memory (NSCache is thread-safe).
enum MapSnapshotCache {
    nonisolated(unsafe) static let shared: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>(); c.countLimit = 120; return c
    }()
    static func key(_ c: CLLocationCoordinate2D, _ s: CGSize, _ scale: CGFloat, _ span: CLLocationDistance) -> NSString {
        String(format: "%.5f,%.5f,%.0fx%.0f@%.0f/%.0f", c.latitude, c.longitude, s.width, s.height, scale, span) as NSString
    }
}

/// Hero image for a place: its real photo when we may show one, otherwise the area map.
struct PlaceHeroImage: View {
    let photoURL: String?
    let coordinate: CLLocationCoordinate2D?
    /// Locked paid place: never show the venue photo before purchase.
    let locked: Bool
    var height: CGFloat = 150
    var credit: Bool = false

    var body: some View {
        if !locked, let photoURL, !photoURL.isEmpty {
            RemoteImage(url: photoURL, height: height, credit: credit)
        } else {
            AreaMapImage(coordinate: coordinate, height: height, locked: locked)
        }
    }
}

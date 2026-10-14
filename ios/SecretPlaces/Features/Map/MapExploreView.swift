import SwiftUI
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var places: [PlaceTeaser] = []
    @Published var selected: PlaceTeaser?

    func load(_ env: AppEnvironment, cityId: String?) async {
        places = (try? await env.places.list(PlaceQuery(cityId: cityId, limit: 500))) ?? []
    }

    /// A region that fits every place in the city, or the city centre when it has none.
    func region(for city: City?) -> MKCoordinateRegion? {
        let coords = places.compactMap(\.approxCoordinate)
        if let minLat = coords.map(\.latitude).min(), let maxLat = coords.map(\.latitude).max(),
           let minLng = coords.map(\.longitude).min(), let maxLng = coords.map(\.longitude).max() {
            return MKCoordinateRegion(
                center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
                span: .init(latitudeDelta: max((maxLat - minLat) * 1.35, 0.04), longitudeDelta: max((maxLng - minLng) * 1.35, 0.04)))
        }
        guard let la = city?.lat, let ln = city?.lng else { return nil }
        return MKCoordinateRegion(center: .init(latitude: la, longitude: ln), span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15))
    }
}

/// Map exploration. Locked places are shown at their APPROX position only —
/// never the exact pin. Exact reveal happens on the detail screen after unlock.
struct MapExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var location: LocationService
    @StateObject private var vm = MapViewModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showCityPicker = false

    var body: some View {
        Map(position: $camera, selection: $vm.selected) {
            ForEach(vm.places) { p in
                if let c = p.approxCoordinate {
                    Marker(p.teaserTitle, systemImage: p.isFreeExperience ? "leaf.fill" : "lock.fill", coordinate: c)
                        .tint(p.isFreeExperience ? Theme.free : Theme.locked)
                        .tag(p)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat))
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Button { showCityPicker = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill").font(.caption).foregroundStyle(Theme.accent)
                        Text(env.selectedCity?.title ?? String(localized: "Choose a city")).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("City: \(env.selectedCity?.title ?? "")"))
                .accessibilityHint(Text("Choose a different city"))
                Text("Locked places show an approximate area, not the exact pin.")
                    .font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
            }.padding(10)
        }
        .sheet(isPresented: $showCityPicker) { CityPickerView() }
        .overlay(alignment: .bottomTrailing) {
            Button { Task { await centerOnUser() } } label: {
                Image(systemName: "location.fill").padding(12).background(.ultraThinMaterial, in: Circle())
            }.padding(16)
        }
        .sheet(item: $vm.selected) { p in
            NavigationStack {
                PlaceDetailView(placeId: p.id, teaser: p)
                    .navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.large])
        }
        .navigationTitle("Map")
        .task(id: env.selectedCityId) {
            await vm.load(env, cityId: env.selectedCityId)
            if let r = vm.region(for: env.selectedCity) {
                withAnimation(.easeInOut(duration: 0.5)) { camera = .region(r) }
            }
            env.analytics.track(.mapOpened)
        }
    }

    private func centerOnUser() async {
        if location.authorization == .notDetermined { location.requestPermission() }
        if let c = await location.requestLocation() {
            camera = .region(MKCoordinateRegion(center: c, span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)))
        }
    }
}

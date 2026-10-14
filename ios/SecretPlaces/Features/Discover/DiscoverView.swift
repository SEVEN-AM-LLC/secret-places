import SwiftUI
import CoreLocation

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var featured: [PlaceTeaser] = []
    @Published var freeToday: [PlaceTeaser] = []
    @Published var editors: [PlaceTeaser] = []
    @Published var newest: [PlaceTeaser] = []
    @Published var events: [EventItem] = []
    @Published var routes: [RouteSummary] = []
    @Published var collections: [PlaceCollection] = []
    @Published var state: LoadState<Bool> = .idle

    /// Everything on Discover is scoped to one city.
    func load(_ env: AppEnvironment, cityId: String?) async {
        state = .loading
        do {
            async let featured = env.places.list(PlaceQuery(cityId: cityId, featuredOnly: true, limit: 10))
            async let free = env.places.list(PlaceQuery(cityId: cityId, freeOnly: true, limit: 10))
            async let editors = env.places.list(PlaceQuery(cityId: cityId, editorsOnly: true, limit: 10))
            async let newest = env.places.list(PlaceQuery(cityId: cityId, limit: 10, orderNewest: true))
            async let events = env.events.upcoming(cityId: cityId, limit: 10)
            async let routes = env.routes.list(cityId: cityId)
            async let collections = env.collections.collections()
            self.featured = try await featured
            self.freeToday = try await free
            self.editors = try await editors
            self.newest = try await newest
            self.events = (try? await events) ?? []
            self.routes = (try? await routes) ?? []
            self.collections = ((try? await collections) ?? []).filter { cityId == nil || $0.cityId == cityId }
            state = .loaded(true)
        } catch let e as AppError {
            state = e == .offline ? .offline : .failed(e)
        } catch { state = .failed(.unknown(error.localizedDescription)) }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = DiscoverViewModel()
    @State private var showSearch = false
    @State private var showCityPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                cityButton
                categoryChips
                switch vm.state {
                case .idle, .loading: LoadingView()
                case .offline: ErrorStateView(error: .offline) { Task { await vm.load(env, cityId: env.selectedCityId) } }
                case .failed(let e): ErrorStateView(error: e) { Task { await vm.load(env, cityId: env.selectedCityId) } }
                default:
                    rail("Featured secrets", vm.featured)
                    collectionsRail
                    eventsRail
                    crawlsRail
                    rail("Free today", vm.freeToday)
                    citiesRail
                    rail("Editor's picks", vm.editors)
                    rail("Newly added", vm.newest)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
        }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showCityPicker) { CityPickerView() }
        .withAppDestinations()
        .task(id: env.selectedCityId) {
            await vm.load(env, cityId: env.selectedCityId)
            env.analytics.track(.discoverView)
        }
    }

    private var cityButton: some View {
        Button { showCityPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill").font(.subheadline).foregroundStyle(Theme.accent)
                Text(env.selectedCity?.title ?? String(localized: "Choose a city"))
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                if let c = env.selectedCity, let flag = env.country(for: c.countryId)?.emojiFlag { Text(flag) }
                Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .accessibilityLabel(Text("City: \(env.selectedCity?.title ?? "")"))
        .accessibilityHint(Text("Choose a different city"))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.categories) { cat in
                    NavigationLink {
                        PlacesListView(title: env.selectedCity.map { "\(cat.title) · \($0.title)" } ?? cat.title,
                                       query: PlaceQuery(cityId: env.selectedCityId, categoryId: cat.id))
                    } label: {
                        HStack(spacing: 6) {
                            if let icon = cat.icon { Image(systemName: icon) }
                            Text(cat.title)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.surface).foregroundStyle(Theme.text)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14)
        }
    }

    private func rail(_ title: LocalizedStringKey, _ places: [PlaceTeaser]) -> some View {
        Group {
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: title).padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(places) { p in
                                NavigationLink(value: p) { PlaceCard(place: p, isSaved: env.savedIds.contains(p.id)).frame(width: 260) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private var eventsRail: some View {
        Group {
            if !vm.events.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "What's on")
                        Spacer()
                        NavigationLink { EventsView() } label: { Text("See all").font(.subheadline).foregroundStyle(Theme.accent) }
                    }.padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.events) { e in
                                NavigationLink(value: e) { EventCard(event: e).frame(width: 260) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private var crawlsRail: some View {
        Group {
            if !vm.routes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Bar crawls")
                        Spacer()
                        NavigationLink { RoutesView() } label: { Text("See all").font(.subheadline).foregroundStyle(Theme.accent) }
                    }.padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.routes) { r in
                                NavigationLink(value: r) { RouteCard(route: r).frame(width: 280) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private var collectionsRail: some View {
        Group {
            if !vm.collections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Collections", subtitle: "Curated loops of hidden places").padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.collections) { c in
                                NavigationLink(value: c) { CollectionCard(collection: c).frame(width: 260) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private var citiesRail: some View {
        let others = env.cities.filter { $0.id != env.selectedCityId }
        return Group {
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Other cities")
                        Spacer()
                        Button { showCityPicker = true } label: { Text("See all").font(.subheadline).foregroundStyle(Theme.accent) }
                    }.padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(others) { city in
                                Button { env.selectCity(city.id) } label: { CityTile(city: city, flag: env.country(for: city.countryId)?.emojiFlag, count: env.placeCounts[city.id] ?? 0) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }
}

/// Compact city card: an area map of the city with its name and how many secrets it has.
struct CityTile: View {
    let city: City
    let flag: String?
    let count: Int
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = city.coverUrl, !cover.isEmpty {
                RemoteImage(url: cover, height: 120)
            } else {
                AreaMapImage(coordinate: city.lat.flatMap { la in city.lng.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } },
                             height: 120, spanMeters: 9000, showsMarker: false)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(flag ?? "") \(city.title)").font(.headline).foregroundStyle(.white)
                Text("\(count) secrets").font(.caption).foregroundStyle(.white.opacity(0.8))
            }.padding(10)
        }
        .frame(width: 200, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

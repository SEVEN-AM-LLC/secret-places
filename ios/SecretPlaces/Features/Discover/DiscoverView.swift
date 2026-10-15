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
    @State private var showSuggest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                categoryChips
                switch vm.state {
                case .idle, .loading: LoadingView()
                case .offline: ErrorStateView(error: .offline) { Task { await vm.load(env, cityId: env.selectedCityId) } }
                case .failed(let e): ErrorStateView(error: e) { Task { await vm.load(env, cityId: env.selectedCityId) } }
                default:
                    secretOfTheDay
                    rail("Featured secrets", vm.featured)
                    collectionsRail
                    eventsRail
                    crawlsRail
                    rail("Free today", vm.freeToday)
                    citiesRail
                    rail("Editor's picks", vm.editors)
                    rail("Newly added", vm.newest)
                }
                suggestCard
            }
            .padding(.vertical, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSuggest = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel(Text("Suggest a place"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
        }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showCityPicker) { CityPickerView() }
        .sheet(isPresented: $showSuggest) { SuggestPlaceView() }
        .withAppDestinations()
        .task(id: env.selectedCityId) {
            await vm.load(env, cityId: env.selectedCityId)
            env.analytics.track(.discoverView)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting).font(.subheadline).foregroundStyle(Theme.textMuted)
            Button { showCityPicker = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(mood).font(Theme.display(34)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading).lineLimit(2).minimumScaleFactor(0.7)
                    if let c = env.selectedCity, let flag = env.country(for: c.countryId)?.emojiFlag { Text(flag).font(.title2) }
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("City: \(env.selectedCity?.title ?? "")"))
            .accessibilityHint(Text("Choose a different city"))
            progressBar
        }
        .padding(.horizontal, 16)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }

    /// "Paris after dark", "Lisbon this morning" — the city in the mood of the hour.
    private var mood: String {
        guard let city = env.selectedCity?.title else { return String(localized: "Choose a city") }
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return String(localized: "\(city) this morning")
        case 12..<17: return String(localized: "\(city) this afternoon")
        case 17..<22: return String(localized: "\(city) tonight")
        default: return String(localized: "\(city) after dark")
        }
    }

    @ViewBuilder private var progressBar: some View {
        let p = env.progress(cityId: env.selectedCityId)
        if p.total > 0 {
            HStack(spacing: 10) {
                if p.found > 0 {
                    ProgressView(value: Double(p.found), total: Double(p.total)).tint(Theme.accent)
                    Text("\(p.found) of \(p.total) found").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).fixedSize()
                } else {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(Theme.accent)
                    Text("\(p.total) secrets to find").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: Secret of the day

    /// One free secret per day, the same for everyone that day — photo-first when we have one.
    private var dailyPick: PlaceTeaser? {
        let pool = (vm.freeToday + vm.featured.filter(\.isFreeExperience) + vm.editors.filter(\.isFreeExperience))
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        let withPhoto = unique.filter { $0.displayPhoto != nil }
        let candidates = withPhoto.isEmpty ? unique : withPhoto
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return candidates.sorted { $0.id < $1.id }[day % candidates.count]
    }

    @ViewBuilder private var secretOfTheDay: some View {
        if let p = dailyPick {
            let style = env.style(forCategory: p.primaryCategoryId)
            NavigationLink(value: p) {
                ZStack(alignment: .bottomLeading) {
                    PlaceHeroImage(photoURL: p.displayPhoto?.url, coordinate: p.approxCoordinate, locked: false, height: 320,
                                   creditText: PlacePhoto.compact(p.displayPhoto?.credit), style: style, seed: p.id, artWhenNoPhoto: true, creditAlignment: .topTrailing)
                    LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Secret of the day", systemImage: "key.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                        Text(p.teaserTitle).font(Theme.display(26)).foregroundStyle(.white)
                            .multilineTextAlignment(.leading).lineLimit(3)
                        HStack(spacing: 6) {
                            Image(systemName: style.symbol)
                            Text(env.category(for: p.primaryCategoryId)?.title ?? "")
                            Text("·")
                            Text("Free today")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(18)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private var suggestCard: some View {
        Button { showSuggest = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(env.selectedCity.map { String(localized: "Know a secret in \($0.title)?") } ?? String(localized: "Know a hidden spot?"))
                        .font(.headline).foregroundStyle(Theme.text)
                    Text("Suggest a place — our editors check every one.").font(.subheadline).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textMuted)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.categories) { cat in
                    NavigationLink {
                        PlacesListView(title: env.selectedCity.map { "\(cat.title) · \($0.title)" } ?? cat.title,
                                       query: PlaceQuery(cityId: env.selectedCityId, categoryId: cat.id))
                    } label: {
                        CategoryChip(category: cat)
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
            if let cover = city.displayCover {
                RemoteImage(url: cover.url, height: 120, creditText: PlacePhoto.compact(cover.credit), creditAlignment: .topTrailing)
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

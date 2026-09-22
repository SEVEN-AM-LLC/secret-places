import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var featured: [PlaceTeaser] = []
    @Published var freeToday: [PlaceTeaser] = []
    @Published var editors: [PlaceTeaser] = []
    @Published var newest: [PlaceTeaser] = []
    @Published var cities: [City] = []
    @Published var events: [EventItem] = []
    @Published var routes: [RouteSummary] = []
    @Published var collections: [PlaceCollection] = []
    @Published var state: LoadState<Bool> = .idle

    func load(_ env: AppEnvironment) async {
        state = .loading
        do {
            async let featured = env.places.list(PlaceQuery(featuredOnly: true, limit: 10))
            async let free = env.places.list(PlaceQuery(freeOnly: true, limit: 10))
            async let editors = env.places.list(PlaceQuery(editorsOnly: true, limit: 10))
            async let newest = env.places.list(PlaceQuery(limit: 10, orderNewest: true))
            async let cities = env.geo.cities()
            async let events = env.events.upcoming(cityId: nil, limit: 10)
            async let routes = env.routes.list(cityId: nil)
            async let collections = env.collections.collections()
            self.featured = try await featured
            self.freeToday = try await free
            self.editors = try await editors
            self.newest = try await newest
            self.cities = try await cities
            self.events = (try? await events) ?? []
            self.routes = (try? await routes) ?? []
            self.collections = (try? await collections) ?? []
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                categoryChips
                switch vm.state {
                case .idle, .loading: LoadingView()
                case .offline: ErrorStateView(error: .offline) { Task { await vm.load(env) } }
                case .failed(let e): ErrorStateView(error: e) { Task { await vm.load(env) } }
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
        .withAppDestinations()
        .task { if case .idle = vm.state { await vm.load(env); env.analytics.track(.discoverView) } }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.categories) { cat in
                    NavigationLink(value: cat) {
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
        Group {
            if !vm.cities.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Explore by city").padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.cities) { city in
                                NavigationLink(value: city) {
                                    ZStack(alignment: .bottomLeading) {
                                        RemoteImage(url: city.coverUrl, height: 120).frame(width: 200)
                                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                        Text(city.title).font(.headline).foregroundStyle(.white).padding(10)
                                    }
                                    .frame(width: 200, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }
            }
        }
    }
}

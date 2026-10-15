import SwiftUI

struct CityView: View {
    let city: City
    @EnvironmentObject private var env: AppEnvironment
    @State private var neighborhoods: [Neighborhood] = []
    @State private var places: [PlaceTeaser] = []
    @State private var events: [EventItem] = []
    @State private var loading = true

    var freeCount: Int { places.filter { $0.isFreeExperience }.count }
    var subtitle: String {
        if places.isEmpty && !events.isEmpty { return "\(events.count)+ events on now" }
        return "\(places.count) Secrets · \(freeCount) Free"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    if let cover = city.displayCover {
                        RemoteImage(url: cover.url, height: 200, creditText: cover.credit, creditAlignment: .topTrailing)
                    } else {
                        RemoteImage(url: nil, height: 200)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(city.title).font(.largeTitle.bold()).foregroundStyle(.white)
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }.padding()
                }
                if let d = city.description { Text(d).font(.body).foregroundStyle(Theme.textMuted).padding(.horizontal, 14) }

                if !events.isEmpty {
                    HStack {
                        SectionHeader(title: "What's on in \(city.title)")
                        Spacer()
                        NavigationLink { EventsView(cityId: city.id) } label: {
                            Text("See all").font(.subheadline).foregroundStyle(Theme.accent)
                        }
                    }.padding(.horizontal, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(events) { e in
                                NavigationLink(value: e) { EventCard(event: e).frame(width: 260) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14)
                    }
                }

                if !neighborhoods.isEmpty {
                    SectionHeader(title: "Explore by neighborhood").padding(.horizontal, 14)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(neighborhoods) { n in
                            NavigationLink(value: n) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(n.title).font(.headline).foregroundStyle(Theme.text)
                                    Text(placeCount(for: n)).font(.caption).foregroundStyle(Theme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).cardBackground()
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 14)
                }

                if !places.isEmpty {
                    SectionHeader(title: "Featured in \(city.title)").padding(.horizontal, 14)
                    ForEach(places.prefix(8)) { p in
                        NavigationLink(value: p) { PlaceCard(place: p, isSaved: env.savedIds.contains(p.id)) }
                            .buttonStyle(.plain).padding(.horizontal, 14)
                    }
                } else if loading { LoadingView() }
            }.padding(.bottom, 30)
        }
        .background(Theme.bg).ignoresSafeArea(edges: .top)
        .navigationTitle(city.title).navigationBarTitleDisplayMode(.inline)
        .withAppDestinations()
        .task { await load() }
    }

    private func placeCount(for n: Neighborhood) -> String {
        let c = places.filter { $0.neighborhoodId == n.id }.count
        return "\(c) Secrets"
    }

    private func load() async {
        env.analytics.track(.cityView(citySlug: city.slug))
        async let hoods = try? env.geo.neighborhoods(cityId: city.id)
        async let pl = try? env.places.list(PlaceQuery(cityId: city.id, limit: 100))
        async let ev = try? env.events.upcoming(cityId: city.id, limit: 12)
        neighborhoods = await hoods ?? []
        places = await pl ?? []
        events = await ev ?? []
        loading = false
    }
}

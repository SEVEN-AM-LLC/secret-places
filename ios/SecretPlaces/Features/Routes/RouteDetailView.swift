import SwiftUI
import MapKit

@MainActor
final class RouteDetailViewModel: ObservableObject {
    @Published var state: LoadState<RouteDetails> = .idle
    @Published var priceLabel = Config.defaultPriceLabel
    @Published var errorMessage: String?

    let slug: String
    init(slug: String) { self.slug = slug }

    func load(_ env: AppEnvironment, purchases: PurchaseService) async {
        if state.value == nil { state = .loading }
        do {
            let details = try await env.routes.details(slug: slug)
            state = .loaded(details)
            priceLabel = details.priceLabel                 // real price from price_cents
            if let pid = details.productId, !details.isFree {
                priceLabel = await purchases.priceLabel(for: pid, fallback: details.priceLabel)
            }
        } catch let e as AppError {
            state = e == .offline ? .offline : .failed(e)
        } catch { state = .failed(.unknown(error.localizedDescription)) }
    }

    func unlock(_ env: AppEnvironment, purchases: PurchaseService) async {
        guard let details = state.value, let productId = details.productId else { return }
        do {
            if let unlocked = try await purchases.purchaseRoute(routeSlug: slug, productId: productId) {
                state = .loaded(unlocked)
            } else {
                await load(env, purchases: purchases)
            }
            await env.entitlements.refresh()
        } catch AppError.purchaseCancelled {
            // silent
        } catch let e as AppError {
            errorMessage = e.errorDescription
        } catch { errorMessage = error.localizedDescription }
    }
}

struct RouteDetailView: View {
    let slug: String
    var summary: RouteSummary?
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm: RouteDetailViewModel
    @State private var showSignIn = false
    @State private var pendingUnlock = false

    init(slug: String, summary: RouteSummary? = nil) {
        self.slug = slug
        self.summary = summary
        _vm = StateObject(wrappedValue: RouteDetailViewModel(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: vm.state.value?.coverUrl ?? summary?.coverUrl, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    .padding(.horizontal, 14)

                switch vm.state {
                case .idle, .loading, .empty: LoadingView()
                case .offline: ErrorStateView(error: .offline) { Task { await vm.load(env, purchases: purchases) } }
                case .failed(let e): ErrorStateView(error: e) { Task { await vm.load(env, purchases: purchases) } }
                case .loaded(let route): content(route)
                }
            }
            .padding(.vertical, 10)
        }
        .background(Theme.bg)
        .navigationTitle(vm.state.value?.title ?? summary?.title ?? "Crawl")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { if let route = vm.state.value { bottomBar(route) } }
        .sheet(isPresented: $showSignIn, onDismiss: {
            if pendingUnlock, auth.isSignedIn { pendingUnlock = false; Task { await vm.unlock(env, purchases: purchases) } }
        }) {
            SignInView(reason: "Sign in to unlock this crawl and keep it across devices.")
        }
        .alert("Purchase failed", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .withAppDestinations()
        .task { await vm.load(env, purchases: purchases) }
    }

    @ViewBuilder private func content(_ route: RouteDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PriceTag(label: route.owned ? String(localized: "Unlocked") : route.priceLabel, isFree: route.isFree || route.owned)
                Label("\(route.stops.count) stops", systemImage: "mappin.circle").font(.caption).foregroundStyle(Theme.textMuted)
                if let d = route.durationMin { Label("\(d) min", systemImage: "clock").font(.caption).foregroundStyle(Theme.textMuted) }
                if let dist = route.distanceM { Label(String(format: "%.1f km", Double(dist)/1000), systemImage: "figure.walk").font(.caption).foregroundStyle(Theme.textMuted) }
            }
            if let s = route.summary { Text(s).font(.body).foregroundStyle(Theme.text) }
            if let d = route.description, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(Theme.textMuted) }

            SectionHeader(title: "The route").padding(.top, 6)
            ForEach(Array(route.stops.enumerated()), id: \.element.id) { idx, stop in
                stopRow(idx: idx, stop: stop, owned: route.owned)
            }

            if !route.owned {
                Text("Stops are hidden until you unlock the crawl. Unlocking reveals every bar and turns on turn-by-turn directions.")
                    .font(.caption).foregroundStyle(Theme.textMuted).padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private func stopRow(idx: Int, stop: RouteStop, owned: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(stop.locked ? Theme.surface2 : Theme.accent.opacity(0.25)).frame(width: 30, height: 30)
                if stop.locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.locked) }
                else { Text("\(idx + 1)").font(.caption.bold()).foregroundStyle(Theme.accent) }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(stop.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if !stop.locked, let biz = stop.businessName, biz != stop.displayTitle {
                    Text(biz).font(.caption).foregroundStyle(Theme.textMuted)
                }
                Text(stop.locked ? stop.teaserDescription : (stop.note ?? stop.teaserDescription))
                    .font(.caption).foregroundStyle(Theme.textMuted).lineLimit(2)
                if stop.locked {
                    if stop.requiresPassword {
                        Label("Password at the door", systemImage: "key.fill")
                            .font(.caption2.weight(.medium)).foregroundStyle(Theme.locked)
                    }
                } else if let pw = stop.entryPassword, !pw.isEmpty {
                    DoorWordCard(password: pw, note: stop.entryNote, compact: true).padding(.top, 2)
                } else if let note = stop.entryNote, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(Theme.accent.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder private func bottomBar(_ route: RouteDetails) -> some View {
        VStack(spacing: 0) {
            if route.owned {
                Button { startCrawl(route) } label: {
                    Label("Start crawl", systemImage: "figure.walk.motion")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(route.stops.compactMap { $0.exactCoordinate }.isEmpty)
            } else {
                Button {
                    if auth.isSignedIn { Task { await vm.unlock(env, purchases: purchases) } }
                    else { pendingUnlock = true; showSignIn = true }
                } label: {
                    HStack {
                        if purchases.purchasingProductId != nil { ProgressView().tint(.black) }
                        Text("Unlock crawl · \(vm.priceLabel)").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(purchases.purchasingProductId != nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Opens Apple Maps with walking directions through every unlocked stop.
    private func startCrawl(_ route: RouteDetails) {
        let items: [MKMapItem] = route.stops.compactMap { stop in
            guard let coord = stop.exactCoordinate else { return nil }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
            item.name = stop.displayTitle
            return item
        }
        guard !items.isEmpty else { return }
        MKMapItem.openMaps(with: items, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

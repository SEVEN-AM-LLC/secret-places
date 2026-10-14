import SwiftUI
import MapKit

@MainActor
final class PlaceDetailViewModel: ObservableObject {
    @Published var state: LoadState<PlaceDetails> = .idle
    @Published var priceLabel = Config.defaultPriceLabel
    @Published var errorMessage: String?

    let placeId: String
    init(placeId: String) { self.placeId = placeId }

    func load(_ env: AppEnvironment, purchases: PurchaseService) async {
        if state.value == nil { state = .loading }
        do {
            let details = try await env.places.details(id: placeId)
            state = .loaded(details)
            if details.isUnlocked { await DiskCache.shared.save(details, key: cacheKey) }
            if let pid = details.productId, details.accessType == .paid {
                priceLabel = await purchases.priceLabel(for: pid)
            }
        } catch let e as AppError {
            if e == .offline, let cached = await DiskCache.shared.load(PlaceDetails.self, key: cacheKey) {
                state = .loaded(cached)      // offline: only cached UNLOCKED places
            } else { state = .failed(e) }
        } catch { state = .failed(.unknown(error.localizedDescription)) }
    }

    private var cacheKey: String { "place_\(placeId)" }

    func unlock(_ env: AppEnvironment, purchases: PurchaseService) async {
        guard let details = state.value, let productId = details.productId else { return }
        do {
            if let unlocked = try await purchases.purchase(placeId: placeId, productId: productId) {
                state = .loaded(unlocked)
                await DiskCache.shared.save(unlocked, key: cacheKey)
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

struct PlaceDetailView: View {
    let placeId: String
    var teaser: PlaceTeaser?
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm: PlaceDetailViewModel
    @State private var showSignIn = false
    @State private var showRate = false
    @State private var pendingUnlock = false

    init(placeId: String, teaser: PlaceTeaser? = nil) {
        self.placeId = placeId
        self.teaser = teaser
        _vm = StateObject(wrappedValue: PlaceDetailViewModel(placeId: placeId))
    }

    var body: some View {
        ScrollView {
            switch vm.state {
            case .idle, .loading: header(fromTeaser: true); LoadingView()
            case .offline: ErrorStateView(error: .offline) { Task { await vm.load(env, purchases: purchases) } }
            case .failed(let e): ErrorStateView(error: e) { Task { await vm.load(env, purchases: purchases) } }
            case .empty: EmptyStateView(icon: "mappin.slash", title: "Not found", message: "This place is unavailable.")
            case .loaded(let d): content(d)
            }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { toolbarMenu } }
        .sheet(isPresented: $showSignIn, onDismiss: { if pendingUnlock, auth.isSignedIn { pendingUnlock = false; Task { await vm.unlock(env, purchases: purchases) } } }) {
            SignInView(reason: "Sign in to unlock and keep your secrets across devices.")
        }
        .sheet(isPresented: $showRate) { if let d = vm.state.value { RatePlaceSheet(place: d) } }
        .alert("Purchase problem", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .task { await vm.load(env, purchases: purchases)
            env.analytics.track(.placePreview(placeId: placeId, locked: !(vm.state.value?.isUnlocked ?? false))) }
    }

    // MARK: Content

    @ViewBuilder private func content(_ d: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PlaceHeroImage(photoURL: d.heroImageUrl,
                           coordinate: d.isUnlocked ? (d.exactCoordinate ?? d.approxCoordinate) : d.approxCoordinate,
                           locked: !d.isUnlocked, height: 240, credit: true)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PriceTag(label: d.priceLabel, isFree: d.accessType == .free || (d.isFreeNow ?? false))
                    if d.ratingsCount > 0 { Label(String(format: "%.1f (%d)", d.rating, d.ratingsCount), systemImage: "star.fill").font(.caption).foregroundStyle(Theme.accent) }
                    Spacer()
                    if let cat = env.category(for: d.primaryCategoryId) { Text(cat.title).font(.caption).foregroundStyle(Theme.textMuted) }
                }
                Text(d.displayTitle).font(.title.bold()).foregroundStyle(Theme.text)
                Text(d.isUnlocked ? (d.fullDescription ?? d.teaserDescription) : d.teaserDescription)
                    .font(.body).foregroundStyle(Theme.textMuted)

                quickFacts(d)

                if d.isUnlocked { unlockedGuide(d) } else { lockedCallToAction(d) }
            }.padding(16)
        }
    }

    private func header(fromTeaser: Bool) -> some View {
        Group { if let t = teaser {
            PlaceHeroImage(photoURL: t.heroImageUrl, coordinate: t.approxCoordinate,
                           locked: !t.isFreeExperience, height: 240, credit: true)
        } }
    }

    private func quickFacts(_ d: PlaceDetails) -> some View {
        FlowChips(chips: [
            d.travelTimeMin.map { "🚶 \($0) min" },
            d.bestTime.map { "🕒 \($0)" },
            d.expectedDurationMin.map { "⏱ \($0) min" },
            d.crowdLevel.map { "👥 \($0)" },
            d.priceLevel.map { String(repeating: "$", count: $0) },
        ].compactMap { $0 })
    }

    // MARK: Locked

    private func unlockTitle(_ d: PlaceDetails) -> String {
        if d.unlocksWithCityPass, let city = d.cityTitle {
            return String(localized: "Unlock all of \(city) · \(vm.priceLabel)")
        }
        return String(localized: "Unlock for \(vm.priceLabel)")
    }

    private func lockedCallToAction(_ d: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.locked)
                Text("The exact place is hidden").font(.headline).foregroundStyle(Theme.text)
            }
            Text("Unlock to reveal the exact location, directions, the full guide and insider tips.")
                .font(.subheadline).foregroundStyle(Theme.textMuted)
            if d.unlocksWithCityPass, let city = d.cityTitle {
                Label("One pass unlocks every secret place in \(city).", systemImage: "ticket.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            if d.requiresPassword { PasswordLockedHint() }
            approxMap(d)
            Button {
                if auth.isSignedIn { Task { await vm.unlock(env, purchases: purchases) } }
                else { pendingUnlock = true; showSignIn = true }
            } label: {
                HStack {
                    if purchases.purchasingProductId != nil { ProgressView().tint(.black) }
                    Text(purchases.purchasingProductId != nil ? "Unlocking…" : unlockTitle(d))
                        .font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            .disabled(purchases.purchasingProductId != nil)

            Button("Restore purchases") { Task { try? await purchases.restore(); await vm.load(env, purchases: purchases) } }
                .font(.footnote).tint(Theme.textMuted)
        }
    }

    // MARK: Unlocked guide

    private func unlockedGuide(_ d: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let pw = d.entryPassword, !pw.isEmpty {
                DoorWordCard(password: pw, note: d.entryNote)
            } else if let note = d.entryNote, !note.isEmpty {
                infoBlock("At the door", note)
            }
            exactMap(d)
            HStack(spacing: 12) {
                if let c = d.exactCoordinate {
                    Button { openAppleMaps(c, name: d.displayTitle) } label: { Label("Apple Maps", systemImage: "map.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.surface2)
                    Button { openGoogleMaps(c) } label: { Label("Google", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(Theme.accent)
                }
            }
            infoBlock("How to find it", d.walkingInstructions)
            infoBlock("Address", d.exactAddress)
            infoBlock("Insider tips", d.insiderTips)
            infoBlock("Parking", d.parkingInfo)
            infoBlock("Photo spot", d.photoSpot)
            infoBlock("Accessibility", d.accessibilityInfo)
            infoBlock("Safety", d.safetyInfo)
            infoBlock("What to bring", d.whatToBring)
            if !d.tags.isEmpty { FlowChips(chips: d.tags.map { "#\($0)" }) }
            HStack(spacing: 12) {
                Button { showRate = true } label: { Label("Rate", systemImage: "star").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(Theme.accent)
                Button { Task { await env.setStatus(placeId, .visited) } } label: {
                    Label(env.placeStatuses[placeId] == .visited ? "Visited" : "Mark visited", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(Theme.free)
            }
        }
    }

    @ViewBuilder private func infoBlock(_ title: String, _ text: String?) -> some View {
        if let t = text, !t.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                Text(t).font(.body).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func approxMap(_ d: PlaceDetails) -> some View {
        Group {
            if let la = d.approxLat, let ln = d.approxLng {
                Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: la, longitude: ln), span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))) {
                    MapCircle(center: .init(latitude: la, longitude: ln), radius: 900)
                        .foregroundStyle(Theme.locked.opacity(0.25)).stroke(Theme.locked, lineWidth: 1)
                }
                .frame(height: 160).clipShape(RoundedRectangle(cornerRadius: Theme.corner)).allowsHitTesting(false)
                .overlay(alignment: .bottom) { Text("Approximate area — unlock to reveal").font(.caption).padding(6).background(.ultraThinMaterial, in: Capsule()).padding(6) }
            }
        }
    }

    private func exactMap(_ d: PlaceDetails) -> some View {
        Group {
            if let c = d.exactCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: c, span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                    Marker(d.displayTitle, coordinate: c).tint(Theme.accent)
                }
                .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: Theme.corner)).allowsHitTesting(false)
            }
        }
    }

    private var toolbarMenu: some View {
        Menu {
            Button { Task { await env.toggleSaved(placeId) } } label: {
                Label(env.savedIds.contains(placeId) ? "Saved" : "Save", systemImage: env.savedIds.contains(placeId) ? "bookmark.fill" : "bookmark")
            }
            Button { Task { await env.setStatus(placeId, .wantToVisit) } } label: { Label("Want to visit", systemImage: "heart") }
            Menu("Report a problem") {
                ForEach(["closed","inaccessible","wrong_coordinates","unsafe","price_changed","duplicate","not_worth","other"], id: \.self) { reason in
                    Button(reason.replacingOccurrences(of: "_", with: " ").capitalized) {
                        Task { try? await env.reports.report(placeId: placeId, reason: reason, details: nil) }
                    }
                }
            }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    private func openAppleMaps(_ c: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    private func openGoogleMaps(_ c: CLLocationCoordinate2D) {
        let gmaps = URL(string: "comgooglemaps://?daddr=\(c.latitude),\(c.longitude)&directionsmode=walking")!
        if UIApplication.shared.canOpenURL(gmaps) { UIApplication.shared.open(gmaps) }
        else if let web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(c.latitude),\(c.longitude)") { UIApplication.shared.open(web) }
    }
}

/// Simple wrapping chips.
struct FlowChips: View {
    let chips: [String]
    var body: some View {
        FlexibleWrap(chips) { chip in
            Text(chip).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surface2).foregroundStyle(Theme.textMuted).clipShape(Capsule())
        }
    }
}

struct RatePlaceSheet: View {
    let place: PlaceDetails
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var score = 5
    @State private var feedback = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Your rating") {
                    Picker("Stars", selection: $score) { ForEach(1...5, id: \.self) { Text("\($0) ★").tag($0) } }.pickerStyle(.segmented)
                    TextField("Optional feedback", text: $feedback, axis: .vertical).lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Rate this secret")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { try? await env.ratings.rate(placeId: place.id, score: score, feedback: feedback.isEmpty ? nil : feedback); dismiss() } }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }.presentationDetents([.medium])
    }
}

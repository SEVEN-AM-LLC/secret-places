import SwiftUI
import MapKit

/// "Suggest a place": a signed-in user sends a spot in their city to the editors' queue.
/// Nothing is published automatically — editors check every suggestion first.
struct SuggestPlaceView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var categorySlug: String?
    @State private var whySpecial = ""
    @State private var tips = ""
    @State private var address = ""
    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    @State private var showSignIn = false

    private var city: City? { env.selectedCity }
    private var canSend: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 2 && whySpecial.trimmingCharacters(in: .whitespaces).count >= 10 && !sending
    }

    var body: some View {
        NavigationStack {
            Group {
                if sent { thanks } else if !auth.isSignedIn { signInPrompt } else { form }
            }
            .background(Theme.bg)
            .navigationTitle("Suggest a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if auth.isSignedIn && !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }.disabled(!canSend)
                    }
                }
            }
            .sheet(isPresented: $showSignIn) { SignInView(reason: String(localized: "Sign in to suggest places — we'll let you know when yours goes live.")) }
            .onAppear(perform: centerOnCity)
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name of the place", text: $title)
                Picker("Category", selection: $categorySlug) {
                    Text("Not sure").tag(String?.none)
                    ForEach(env.categories) { Text($0.title).tag(Optional($0.slug)) }
                }
            } footer: {
                if let city { Text("In \(city.title)") }
            }

            Section("Why is it special?") {
                TextField("What makes it worth finding?", text: $whySpecial, axis: .vertical).lineLimit(3...8)
            }

            Section {
                TextField("Address or how to find it (optional)", text: $address, axis: .vertical).lineLimit(1...3)
                TextField("Tips: best time, what to order… (optional)", text: $tips, axis: .vertical).lineLimit(1...4)
            }

            Section {
                ZStack {
                    Map(position: $camera)
                        .onMapCameraChange(frequency: .onEnd) { pin = $0.region.center }
                    Image(systemName: "mappin").font(.title.weight(.bold)).foregroundStyle(Theme.accent)
                        .offset(y: -12).allowsHitTesting(false)
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
                if location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways {
                    Button { Task { await useMyLocation() } } label: { Label("I'm there now", systemImage: "location.fill") }
                }
            } header: {
                Text("Where is it?")
            } footer: {
                Text("Move the map so the pin sits on the place.")
            }

            Section {
                if let error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Our editors check every suggestion before it appears in the app. Please don't send private homes or places that aren't open to visitors.")
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(sending)
    }

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 46)).foregroundStyle(Theme.accent)
            Text("Know a hidden spot?").font(.title2.bold()).foregroundStyle(Theme.text)
            Text("Sign in to suggest it. Editors review every place before it's added.")
                .font(.subheadline).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            Button("Sign in with Apple") { showSignIn = true }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(Theme.free)
            Text("Thank you!").font(.title2.bold()).foregroundStyle(Theme.text)
            Text("Our editors will take a look. If it's a real secret, it'll show up in \(city?.title ?? String(localized: "the app")).")
                .font(.subheadline).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centerOnCity() {
        guard pin == nil, let lat = city?.lat, let lng = city?.lng else { return }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        pin = c
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000))
    }

    private func useMyLocation() async {
        guard let c = await location.requestLocation() else { return }
        pin = c
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600))
    }

    private func send() async {
        sending = true; error = nil
        defer { sending = false }
        let trimmed = { (s: String) -> String? in let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        let suggestion = PlaceSuggestion(cityId: city?.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                         categorySlug: categorySlug, whySpecial: whySpecial.trimmingCharacters(in: .whitespacesAndNewlines),
                                         tips: trimmed(tips), address: trimmed(address), lat: pin?.latitude, lng: pin?.longitude)
        do {
            try await env.suggestions.submit(suggestion)
            env.analytics.track(.suggestPlace)
            sent = true
        } catch AppError.notAuthenticated {
            showSignIn = true
        } catch AppError.server(_, let message) where message.contains("too_many_suggestions") {
            error = String(localized: "That's a lot of secrets for one day — try again tomorrow.")
        } catch {
            self.error = String(localized: "Couldn't send right now. Please try again.")
        }
    }
}

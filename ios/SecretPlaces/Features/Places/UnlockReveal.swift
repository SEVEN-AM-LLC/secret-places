import SwiftUI
import MapKit

/// The moment a secret opens: rings burst out, the lock springs open, the real name appears.
struct UnlockRevealView: View {
    let details: PlaceDetails
    let style: CategoryStyle
    let progress: (found: Int, total: Int)
    var onDone: () -> Void

    @State private var opened = false
    @State private var rings = false
    @State private var showText = false

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    ForEach(0..<3) { i in
                        Circle().stroke(style.tint.opacity(0.5 - Double(i) * 0.14), lineWidth: 1.5)
                            .frame(width: 130, height: 130)
                            .scaleEffect(rings ? 1.6 + CGFloat(i) * 0.55 : 0.6)
                            .opacity(rings ? 0 : 1)
                            .animation(.easeOut(duration: 1.3).delay(Double(i) * 0.15), value: rings)
                    }
                    Circle().fill(style.deep).frame(width: 130, height: 130)
                        .overlay(Circle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    Image(systemName: opened ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(opened ? -12 : 0))
                        .scaleEffect(opened ? 1.08 : 0.9)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(height: 220)

                VStack(spacing: 8) {
                    Text("Secret \(SecretNumber.label(details.id)) unlocked")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    Text(details.displayTitle)
                        .font(Theme.display(30)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    if let address = details.exactAddress {
                        Text(address).font(.subheadline).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
                    }
                    if details.accessType == .paid, details.unlocksWithCityPass, let city = details.cityTitle, progress.total > 0 {
                        Text("Every secret in \(city) is yours — \(progress.total) of them.")
                            .font(.footnote).foregroundStyle(Theme.textMuted).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .opacity(showText ? 1 : 0).offset(y: showText ? 0 : 14)

                Spacer()
                VStack(spacing: 10) {
                    if let c = details.exactCoordinate {
                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: c)); item.name = details.displayTitle
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                        } label: {
                            Label("Walk me there", systemImage: "figure.walk").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                    }
                    Button("See the full guide", action: onDone).font(.subheadline).tint(Theme.textMuted)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .opacity(showText ? 1 : 0)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { opened = true }
            rings = true
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.5)) { showText = true }
        }
    }
}

/// A short celebration when a visit earns a badge.
struct AchievementToast: View {
    let achievement: Achievement
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.symbol).font(.title2).foregroundStyle(.black)
                .frame(width: 44, height: 44).background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge earned").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(achievement.title).font(Theme.display(18)).foregroundStyle(Theme.text)
                Text(achievement.detail).font(.caption).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

/// "I've been here" — stamps the place as visited and shows the city progress.
struct VisitedStampButton: View {
    let placeId: String
    let cityId: String?
    let cityTitle: String?
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @State private var stamped = false
    @State private var showSignIn = false

    var body: some View {
        let visited = env.placeStatuses[placeId] == .visited
        let p = env.progress(cityId: cityId)
        Button {
            guard !visited else { return }
            guard auth.isSignedIn else { showSignIn = true; return }   // visits live in the account
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { stamped = true }
            Task { await env.setStatus(placeId, .visited) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: visited ? "checkmark.seal.fill" : "seal")
                    .font(.title2).foregroundStyle(visited ? Theme.free : Theme.accent)
                    .scaleEffect(stamped ? 1.25 : 1).rotationEffect(.degrees(stamped ? -10 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text(visited ? "You've been here" : "I've been here").font(.headline).foregroundStyle(Theme.text)
                    if let cityTitle, p.total > 0 {
                        Text("\(p.found) of \(p.total) secrets found in \(cityTitle)").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSignIn) { SignInView(reason: String(localized: "Sign in to collect the secrets you find and earn badges.")) }
        .onChange(of: stamped) { _, s in
            if s { Task { try? await Task.sleep(for: .milliseconds(300)); withAnimation(.spring) { stamped = false } } }
        }
    }
}

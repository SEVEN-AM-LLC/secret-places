import SwiftUI

/// In-app language override, applied app-wide via the `AppleLanguages` default.
/// "system" follows the device order; uk/en force that language. The change
/// takes full effect (including UIKit nav titles and String(localized:)) after
/// the app is relaunched.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, uk, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .uk: return "Українська"
        case .en: return "English"
        }
    }
    /// The current effective choice, derived from the stored AppleLanguages.
    static var current: AppLanguage {
        guard let langs = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
              let first = langs.first else { return .system }
        if first.hasPrefix("uk") { return .uk }
        if first.hasPrefix("en") { return .en }
        return .system
    }
    /// Persist the choice into AppleLanguages (read by the OS at launch).
    func apply() {
        let key = "AppleLanguages"
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: key)
        case .uk: UserDefaults.standard.set(["uk"], forKey: key)
        case .en: UserDefaults.standard.set(["en"], forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
}

@main
struct SecretPlacesApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.auth)
                .environmentObject(env.purchases)
                .environmentObject(env.location)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await env.bootstrap() }
        }
    }
}

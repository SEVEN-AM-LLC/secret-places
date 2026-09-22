import SwiftUI

/// In-app language override. "system" follows the device; otherwise force uk/en.
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
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .uk: return Locale(identifier: "uk")
        case .en: return Locale(identifier: "en")
        }
    }
}

@main
struct SecretPlacesApp: App {
    @StateObject private var env = AppEnvironment()
    @AppStorage("app_language") private var appLanguage = AppLanguage.system.rawValue

    private var overrideLocale: Locale {
        AppLanguage(rawValue: appLanguage)?.locale ?? Locale.autoupdatingCurrent
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.auth)
                .environmentObject(env.purchases)
                .environmentObject(env.location)
                .environment(\.locale, overrideLocale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await env.bootstrap() }
        }
    }
}

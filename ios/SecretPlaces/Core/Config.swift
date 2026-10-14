import Foundation

/// App configuration, read from Info.plist (injected via xcconfig/project settings).
enum Config {
    static let supabaseURL: URL = {
        let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        return URL(string: s) ?? URL(string: "https://api.secretplaces.7am.agency")!
    }()

    static let supabaseAnonKey: String =
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkxOTc1OTM1LCJleHAiOjE5NDk2NTU5MzV9.8ilKUy_FcMjIIqyCOfrDoqVUdh0qo_HZDsRRESsBFDo"

    /// Default unlock price shown before StoreKit products load.
    static let defaultPriceLabel = "$0.99"

    static var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }
    static var authURL: URL { supabaseURL.appendingPathComponent("auth/v1") }
    static var functionsURL: URL { supabaseURL.appendingPathComponent("functions/v1") }
}

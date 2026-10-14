import Foundation
import Combine

/// Thread-safe holder for the current session (token + user id), read by the
/// network client and repositories from any context, written by AuthStore on
/// the main actor.
final class TokenHolder: SessionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?
    private var _userId: String?
    var accessToken: String? { lock.lock(); defer { lock.unlock() }; return _token }
    var userId: String? { lock.lock(); defer { lock.unlock() }; return _userId }
    var isSignedIn: Bool { accessToken != nil }
    func set(token: String?, userId: String?) { lock.lock(); _token = token; _userId = userId; lock.unlock() }
}

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var email: String?
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
    struct AuthUser: Decodable { let id: String; let email: String? }
}

@MainActor
protocol AuthServicing: AnyObject {
    var currentUserId: String? { get }
    var isSignedIn: Bool { get }
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws
    func signOut()
}

/// Sign in with Apple → Supabase session. Guest browsing is the default (no session).
@MainActor
final class AuthStore: ObservableObject, AuthServicing {
    @Published private(set) var session: AuthSession?
    let tokens = TokenHolder()

    private let storageKey = "sp_auth_session"

    init() {
        // One-time migration: older builds kept the session in UserDefaults.
        if let legacy = UserDefaults.standard.data(forKey: storageKey) {
            Keychain.set(legacy, for: storageKey)
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        if let data = Keychain.data(for: storageKey),
           let s = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = s
            tokens.set(token: s.accessToken, userId: s.userId)
        }
    }

    var currentUserId: String? { session?.userId }
    var isSignedIn: Bool { session != nil }

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws {
        var comps = URLComponents(url: Config.authURL.appendingPathComponent("token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.server(status: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                                  message: String(data: data, encoding: .utf8) ?? "auth failed")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tr = try decoder.decode(TokenResponse.self, from: data)
        let s = AuthSession(accessToken: tr.accessToken, refreshToken: tr.refreshToken, userId: tr.user.id, email: tr.user.email)
        apply(s)
    }

    func signOut() {
        session = nil
        tokens.set(token: nil, userId: nil)
        Keychain.delete(storageKey)
    }

    /// Called on a 401. Tries to refresh the access token with the refresh token;
    /// if that fails (e.g. revoked), signs out so the client falls back to anon.
    /// Returns true when a retry should be attempted (with a fresh or anon token).
    func refreshSession() async -> Bool {
        guard let refreshToken = session?.refreshToken else { return false }
        var comps = URLComponents(url: Config.authURL.appendingPathComponent("token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            return false   // offline / transport error: keep the session, don't retry
        }
        guard let http = resp as? HTTPURLResponse else { return false }
        if (500..<600).contains(http.statusCode) { return false }   // server hiccup: keep the session
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(http.statusCode),
              let tr = try? decoder.decode(TokenResponse.self, from: data) else {
            signOut()   // refresh token rejected → continue as guest
            return true
        }
        apply(AuthSession(accessToken: tr.accessToken, refreshToken: tr.refreshToken, userId: tr.user.id, email: tr.user.email))
        return true
    }

    private func apply(_ s: AuthSession) {
        session = s
        tokens.set(token: s.accessToken, userId: s.userId)
        if let data = try? JSONEncoder().encode(s) { Keychain.set(data, for: storageKey) }
    }
}

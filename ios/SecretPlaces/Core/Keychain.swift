import Foundation
import Security

/// Minimal generic-password Keychain wrapper for small secrets (the auth session).
/// Items are device-only and readable after first unlock (needed for background refresh).
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.secretplaces.app"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func data(for key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func set(_ data: Data, for key: String) {
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query(key).merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

import Foundation
import Security

/// Stores the WriterFlow device access + refresh tokens (ADR-0012) in the
/// app's own Keychain item — deliberately separate from `KeychainStore`'s
/// BYO Azure key item (Stage 5.2: "Store the WriterFlow access + refresh
/// tokens in the app's own Keychain item (WhenUnlockedThisDeviceOnly, no
/// access group). Local DB keys remain a separate item.").
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is stricter than the BYO
/// key's `AfterFirstUnlock` accessibility — these tokens are more sensitive
/// (bearer credentials for a live account, not a user-owned provider key)
/// and never need to be read while the device is locked. No access group is
/// set, so this item is never shared with another app/extension.
enum DeviceTokenKeychain {
    private static let service = "com.karan.writerflow.device-session"
    private static let account = "writerflow-tokens"

    struct StoredTokens: Codable, Equatable, Sendable {
        let deviceID: String
        let accessToken: String
        let accessTokenExpiresAt: Date
        let refreshToken: String
    }

    static func read() -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    @discardableResult
    static func write(_ tokens: StoredTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        delete()

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

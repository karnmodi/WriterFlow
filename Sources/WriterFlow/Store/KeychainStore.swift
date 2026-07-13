import Foundation
import Security

enum KeychainStore {
    private static let service = "com.karan.writerflow"
    private static let account = "azure-openai-api-key"

    static func readAPIKey() -> String? {
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
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let update = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if update == errSecSuccess { return true }
        if update == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Seed Keychain from `.env` on first launch if no key is stored yet.
    static func seedFromEnvIfNeeded(_ env: [String: String], keyEnvName: String) {
        guard readAPIKey() == nil, let key = env[keyEnvName], !key.isEmpty else { return }
        if saveAPIKey(key) {
            Log.store.info("Seeded Azure API key into Keychain from env (\(keyEnvName, privacy: .public))")
        }
    }
}

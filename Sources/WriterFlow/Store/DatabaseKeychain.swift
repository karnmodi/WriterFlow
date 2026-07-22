import Foundation
import Security

/// Stores the local SQLCipher database key (Stage 5.3 "Store refactor":
/// "Generate a random 256-bit local database key from system randomness and
/// store it in a dedicated account-scoped `WhenUnlockedThisDeviceOnly`
/// Keychain item... Do not derive the DB key from password, OAuth token,
/// refresh token, email, or network state."). Deliberately its own Keychain
/// item, separate from `DeviceTokenKeychain`'s bearer tokens and
/// `KeychainStore`'s BYO Azure key — losing/rotating one must never affect
/// the others.
///
/// "Account-scoped" here means the Keychain account label is namespaced by
/// the immutable `(issuer, subject)` identity hash the app is bound to
/// (Stage 5.3's "Bind one immutable (issuer, subject) account to the macOS
/// profile"), not that this type knows anything about sign-in state itself —
/// callers pass the scope in. A caller with no signed-in identity yet should
/// use `unscoped` so local-only (never-signed-in) usage still gets a real
/// encrypted database.
enum DatabaseKeychain {
    private static let service = "com.karan.writerflow.database-key"

    /// The Keychain account label for a given scope. `nil` means no bound
    /// identity yet — a single local/offline database predating any sign-in.
    static func account(forScope scope: String?) -> String {
        guard let scope, !scope.isEmpty else { return "unscoped" }
        return "account-\(scope)"
    }

    /// internal (not `private`) so a test can assert it never grows a
    /// `kSecAttrAccessGroup` key, matching `DeviceTokenKeychain`'s pattern.
    static func baseQuery(scope: String?) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(forScope: scope)
        ]
    }

    static func read(scope: String?) -> Data? {
        var query = baseQuery(scope: scope)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    @discardableResult
    static func write(_ key: Data, scope: String?) -> Bool {
        delete(scope: scope)

        var add = baseQuery(scope: scope)
        add[kSecValueData as String] = key
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(scope: String?) {
        SecItemDelete(baseQuery(scope: scope) as CFDictionary)
    }

    /// 256-bit key from `SecRandomCopyBytes` — never derived from a
    /// password, OAuth token, refresh token, email, or network state.
    static func generateKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(bytes)
    }

    /// Returns the existing key for `scope`, or generates, stores, and
    /// returns a new one if none exists yet. This is the only path that
    /// should ever be used to obtain a key for opening a database — it
    /// guarantees the same random key is reused across launches instead of
    /// silently minting a new one and orphaning previously-encrypted data.
    static func keyOrCreate(scope: String?) -> Data {
        if let existing = read(scope: scope) {
            return existing
        }
        let key = generateKey()
        precondition(write(key, scope: scope), "failed to persist a newly generated database key to the Keychain")
        return key
    }
}

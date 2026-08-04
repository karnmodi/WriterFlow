import Foundation
import Security

/// Stores the local SQLCipher database key (Stage 5.3 "Store refactor":
/// generate a random 256-bit key from system randomness and store it in a
/// dedicated account-scoped Keychain item. Do not derive the DB key from
/// password, OAuth token, refresh token, email, or network state.).
/// Accessibility is `AfterFirstUnlockThisDeviceOnly` so launch-at-login can
/// unlock the DB after the first unlock of a boot without racing an
/// interactive Keychain prompt. Deliberately its own Keychain item, separate
/// from `DeviceTokenKeychain`'s bearer tokens and `KeychainStore`'s BYO
/// Azure key — losing/rotating one must never affect the others.
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
    private static let preferredAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

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

    /// Per-scope mirror of the Keychain items. Opening the database consults
    /// up to four scopes (scope probe, unscoped bind, existing key, unscoped
    /// repair); each uncached read is a potential password prompt, so a single
    /// launch used to be able to stack several of them.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [String: Data?] = [:]

        /// `body` runs only on a miss, while holding the lock, so concurrent
        /// callers cannot each trigger their own Keychain prompt. A load that
        /// reports `cacheable: false` is not stored, so a refused prompt does
        /// not harden into "this key does not exist" for the whole launch.
        func value(forAccount account: String, orLoad body: () -> (data: Data?, cacheable: Bool)) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = keys[account] { return cached }
            let loaded = body()
            if loaded.cacheable { keys[account] = loaded.data }
            return loaded.data
        }

        func set(_ newValue: Data?, forAccount account: String) {
            lock.lock()
            defer { lock.unlock() }
            keys[account] = newValue
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            keys.removeAll()
        }
    }

    static func read(scope: String?) -> Data? {
        let account = account(forScope: scope)
        return cache.value(forAccount: account) {
            let query = baseQuery(scope: scope)
            let result = KeychainItem.read(query, label: "database key")
            if result.wasDenied {
                Log.store.error("Database key read was denied — not caching, so Retry can prompt again")
            }
            if result.data != nil {
                KeychainItem.ensureAccessible(
                    preferredAccessible,
                    baseQuery: query,
                    label: "database key"
                )
            }
            return (result.data, !result.wasDenied)
        }
    }

    @discardableResult
    static func write(_ key: Data, scope: String?) -> Bool {
        let stored = KeychainItem.write(
            key,
            baseQuery: baseQuery(scope: scope),
            accessible: preferredAccessible,
            label: "database key"
        )
        if stored { cache.set(key, forAccount: account(forScope: scope)) }
        return stored
    }

    static func delete(scope: String?) {
        KeychainItem.delete(baseQuery(scope: scope))
        cache.set(nil, forAccount: account(forScope: scope))
    }

    /// Test seam — drops the in-process mirror so the next `read` goes back to
    /// the Keychain.
    static func invalidateCache() {
        cache.invalidate()
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

    /// Copies the pre-sign-in key into the first immutable account scope.
    /// The key bytes stay unchanged, so an already-open SQLCipher database
    /// remains valid while future launches use the account-scoped item.
    static func bindUnscopedKey(to scope: String) -> Bool {
        if read(scope: scope) != nil { return true }
        guard let unscoped = read(scope: nil) else { return false }
        return write(unscoped, scope: scope)
    }

    /// Overwrites an account-scoped key with the pre-sign-in key. Used when the
    /// scoped item was minted separately and no longer decrypts the on-disk
    /// database (the ciphertext was encrypted with `unscoped`).
    static func repairAccountKeyFromUnscoped(scope: String) -> Bool {
        guard let unscoped = read(scope: nil) else { return false }
        if read(scope: scope) == unscoped { return true }
        return write(unscoped, scope: scope)
    }
}

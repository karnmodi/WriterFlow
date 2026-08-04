import Foundation
import Security

/// Stores the WriterFlow device access + refresh tokens (ADR-0012) in the
/// app's own Keychain item — deliberately separate from `KeychainStore`'s
/// BYO Azure key item. Local DB keys remain a separate item. Accessibility is
/// `AfterFirstUnlockThisDeviceOnly` so launch-at-login can read tokens after
/// the first unlock of a boot without racing an interactive Keychain prompt.
/// No access group is set, so this item is never shared with another
/// app/extension.
enum DeviceTokenKeychain {
    /// Shared with `DatabaseKeychain` / `KeychainStore` so login-at-login and
    /// cold start share one accessibility class.
    static let preferredAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    private static let productionService = "com.karan.writerflow.device-session"
    private static let account = "writerflow-tokens"

    /// Test seam. Without it `swift test` operates on the real item: it
    /// overwrites the user's actual sign-in, and because the unsigned test
    /// binary does not own an item the signed app created, its cleanup
    /// `SecItemDelete` silently fails and leaves state behind.
    nonisolated(unsafe) static var serviceOverrideForTesting: String?

    private static var service: String { serviceOverrideForTesting ?? productionService }

    struct StoredTokens: Codable, Equatable, Sendable {
        let deviceID: String
        let accessToken: String
        let accessTokenExpiresAt: Date
        let refreshToken: String
    }

    /// The query shared by every Keychain operation on this item — internal
    /// (not `private`) so a test can assert it never grows a
    /// `kSecAttrAccessGroup` key, which would silently scope these tokens to
    /// a shared group instead of this app alone.
    static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Mirrors the Keychain item for the lifetime of the process. `read()` is
    /// called from `DeviceSessionStore.init` and again from every
    /// `accessToken()`, so without this a single launch could cost the user
    /// several identical Keychain prompts.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: StoredTokens?
        private var isPopulated = false

        /// `body` runs only on a miss, while holding the lock, so concurrent
        /// callers cannot each trigger their own Keychain prompt. A load that
        /// reports `cacheable: false` is not stored — a refused prompt must not
        /// harden into "signed out" for the rest of the launch.
        func value(orLoad body: () -> (tokens: StoredTokens?, cacheable: Bool)) -> StoredTokens? {
            lock.lock()
            defer { lock.unlock() }
            if isPopulated { return tokens }
            let loaded = body()
            if loaded.cacheable {
                tokens = loaded.tokens
                isPopulated = true
            }
            return loaded.tokens
        }

        func set(_ newValue: StoredTokens?) {
            lock.lock()
            defer { lock.unlock() }
            tokens = newValue
            isPopulated = true
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            tokens = nil
            isPopulated = false
        }
    }

    static func read() -> StoredTokens? {
        cache.value {
            let result = KeychainItem.read(baseQuery(), label: "device tokens")
            if result.wasDenied {
                Log.store.error("Device token read was denied — not caching, so a later call can prompt again")
            }
            let tokens = result.data.flatMap { try? JSONDecoder().decode(StoredTokens.self, from: $0) }
            if tokens != nil {
                KeychainItem.ensureAccessible(
                    preferredAccessible,
                    baseQuery: baseQuery(),
                    label: "device tokens"
                )
            }
            return (tokens, !result.wasDenied)
        }
    }

    @discardableResult
    static func write(_ tokens: StoredTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        let stored = KeychainItem.write(
            data,
            baseQuery: baseQuery(),
            accessible: preferredAccessible,
            label: "device tokens"
        )
        if stored { cache.set(tokens) }
        return stored
    }

    static func delete() {
        KeychainItem.delete(baseQuery())
        cache.set(nil)
    }

    /// Test seam — drops the in-process mirror so the next `read()` goes back
    /// to the Keychain.
    static func invalidateCache() {
        cache.invalidate()
    }
}

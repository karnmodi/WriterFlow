import Foundation
import Security

/// Shared low-level plumbing for WriterFlow's generic-password items (the BYO
/// Azure key, the SQLCipher database key, and the device tokens).
///
/// Local installs are signed with a stable certificate ("WriterFlow Local
/// Signing"); public DMGs remain ad-hoc (ADR-0010). Either way, login-keychain
/// items carry an ACL keyed on the calling app's code-signing identity. Two
/// consequences shape this file:
///
/// 1. `SecItemDelete` + `SecItemAdd` replaces the item, and with it the ACL —
///    discarding any "Always Allow" the user granted. Writes go through
///    `SecItemUpdate` whenever the item already exists, and never fall back to
///    delete+recreate on update failure.
/// 2. Every read by a binary the ACL does not cover costs the user a password
///    prompt, so callers must read once per launch and cache, never re-read per
///    call site.
enum KeychainItem {
    struct ReadResult {
        let data: Data?
        let status: OSStatus

        /// The read failed for a reason the user can act on (denied the prompt,
        /// or the keychain was locked) as opposed to the item simply not
        /// existing yet. Callers must not silently treat this as "no value" —
        /// that path recreates keys and orphans encrypted data.
        var wasDenied: Bool {
            switch status {
            case errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed, errSecInteractionRequired:
                return true
            default:
                return false
            }
        }
    }

    static func read(_ baseQuery: [String: Any], label: StaticString) -> ReadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess, status != errSecItemNotFound {
            Log.store.error(
                "Keychain read of \(label, privacy: .public) failed with OSStatus \(status, privacy: .public)"
            )
        }
        guard status == errSecSuccess, let data = item as? Data else {
            return ReadResult(data: nil, status: status)
        }
        return ReadResult(data: data, status: status)
    }

    /// Writes `data`, preserving the existing item's ACL where one exists.
    /// On update failure (other than not-found), returns `false` without
    /// recreating — recreate would wipe "Always Allow".
    @discardableResult
    static func write(
        _ data: Data,
        baseQuery: [String: Any],
        accessible: CFString,
        label: StaticString
    ) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        if updateStatus != errSecItemNotFound {
            Log.store.error(
                "Keychain update of \(label, privacy: .public) failed with OSStatus \(updateStatus, privacy: .public); not recreating (would wipe Always Allow)"
            )
            return false
        }

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Log.store.error(
                "Keychain add of \(label, privacy: .public) failed with OSStatus \(addStatus, privacy: .public)"
            )
        }
        return addStatus == errSecSuccess
    }

    /// Migrates an existing item's accessibility class in place (no delete).
    /// Safe to call after a successful read — used to lift older
    /// `WhenUnlockedThisDeviceOnly` items to `AfterFirstUnlockThisDeviceOnly`
    /// so login-at-login does not race the interactive unlock prompt.
    static func ensureAccessible(
        _ accessible: CFString,
        baseQuery: [String: Any],
        label: StaticString
    ) {
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecAttrAccessible as String: accessible] as CFDictionary
        )
        if status != errSecSuccess, status != errSecItemNotFound {
            Log.store.error(
                "Keychain accessibility migrate of \(label, privacy: .public) failed with OSStatus \(status, privacy: .public)"
            )
        }
    }

    static func delete(_ baseQuery: [String: Any]) {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

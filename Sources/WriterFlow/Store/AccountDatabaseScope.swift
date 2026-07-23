import CryptoKit
import Foundation

/// Content-free account binding for the local SQLCipher database key
/// (Stage 5.3). The opaque hash is persisted in `UserDefaults` so the
/// encrypted store can reopen offline or signed-out; it is never derived from
/// email, tokens, or network state.
enum AccountDatabaseScope {
    private static let boundIdentityHashKey = "com.karan.writerflow.boundIdentityHash"
    private static let entraIssuerKey = "com.karan.writerflow.deviceSession.entraIssuer"
    private static let entraSubjectKey = "com.karan.writerflow.deviceSession.entraSubject"

    /// Opaque SHA-256 hex digest of the immutable `(issuer, subject)` pair.
    static var boundIdentityHash: String? {
        get {
            guard let value = UserDefaults.standard.string(forKey: boundIdentityHashKey),
                  !value.isEmpty else { return nil }
            return value
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: boundIdentityHashKey)
            } else {
                UserDefaults.standard.removeObject(forKey: boundIdentityHashKey)
            }
        }
    }

    /// Scope passed to `DatabaseKeychain.keyOrCreate(scope:)` — `nil` when no
    /// identity is bound yet (local-only / pre-sign-in).
    static var currentDatabaseKeyScope: String? {
        boundIdentityHash
    }

    /// One-way hash of the immutable Entra identity pair — never use email.
    static func identityHash(issuer: String, subject: String) -> String {
        var material = Data()
        material.append(contentsOf: issuer.utf8)
        material.append(0)
        material.append(contentsOf: subject.utf8)
        let digest = SHA256.hash(data: material)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Records issuer/subject from a device session when they become available.
    /// Returns false for a different identity once this macOS profile is bound.
    @discardableResult
    static func recordDeviceSessionIdentity(issuer: String, subject: String) -> Bool {
        let incomingHash = identityHash(issuer: issuer, subject: subject)
        if let existing = boundIdentityHash, existing != incomingHash {
            return false
        }
        UserDefaults.standard.set(issuer, forKey: entraIssuerKey)
        UserDefaults.standard.set(subject, forKey: entraSubjectKey)
        bindIdentityIfUnbound(issuer: issuer, subject: subject)
        return true
    }

    /// Extracts only the WriterFlow JWT's non-secret issuer/subject claims.
    /// Signature/authentication is still enforced by APIM and the API; this
    /// local decode is solely for binding encrypted storage to that identity.
    @discardableResult
    static func recordWriterFlowAccessTokenIdentity(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issuer = payload["iss"] as? String,
              let subject = payload["sub"] as? String,
              !issuer.isEmpty,
              !subject.isEmpty else { return true }
        return recordDeviceSessionIdentity(issuer: issuer, subject: subject)
    }

    /// Applies a cached device-session identity pair if the profile has not
    /// been bound yet — safe to call before opening the database.
    static func syncBindingFromDeviceSessionDefaults() {
        guard boundIdentityHash == nil,
              let issuer = UserDefaults.standard.string(forKey: entraIssuerKey),
              let subject = UserDefaults.standard.string(forKey: entraSubjectKey),
              !issuer.isEmpty, !subject.isEmpty else { return }
        bindIdentityIfUnbound(issuer: issuer, subject: subject)
    }

    @discardableResult
    static func bindIdentityIfUnbound(issuer: String, subject: String) -> String {
        if let existing = boundIdentityHash {
            return existing
        }
        let hash = identityHash(issuer: issuer, subject: subject)
        if DatabaseKeychain.read(scope: nil) != nil {
            precondition(
                DatabaseKeychain.bindUnscopedKey(to: hash),
                "failed to bind the encrypted database key to the account"
            )
        }
        boundIdentityHash = hash
        return hash
    }

    /// Clears the macOS-profile binding so a newly approved WriterFlow account
    /// can take over this Mac. Prior account-scoped encrypted databases remain
    /// on disk under their identity-hash folders and are not opened.
    static func clearBindingForAccountSwitch() {
        boundIdentityHash = nil
        UserDefaults.standard.removeObject(forKey: entraIssuerKey)
        UserDefaults.standard.removeObject(forKey: entraSubjectKey)
        Log.store.notice("Cleared local WriterFlow account binding for account switch")
    }

    /// Test-only reset — production code must never call this.
    static func resetForTesting() {
        clearBindingForAccountSwitch()
    }
}

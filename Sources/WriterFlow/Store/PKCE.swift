import CryptoKit
import Foundation

/// RFC 7636 PKCE S256 — used by device pairing (ADR-0011) exactly as the
/// backend expects: services/api/src/crypto/pkce.ts computes the same
/// transform server-side at `/v2/device/token`.
enum PKCE {
    struct Pair: Sendable {
        let verifier: String
        let challenge: String
    }

    /// 32 random bytes, base64url-encoded (43 chars, no padding) — within
    /// RFC 7636's required 43-128 character range for a code_verifier.
    static func generate() -> Pair {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let verifier = base64URLEncode(Data(bytes))
        return Pair(verifier: verifier, challenge: challenge(for: verifier))
    }

    /// BASE64URL(SHA256(ASCII(verifier))) — the S256 transform, computed
    /// independently here so a test can prove it matches the server's.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

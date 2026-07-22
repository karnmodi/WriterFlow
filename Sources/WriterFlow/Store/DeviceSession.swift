import Foundation

/// V2-ARCHITECTURE.md §4.1 / §5.1 (ADR-0011, ADR-0012). The Mac app is never
/// an Entra/OAuth client — this is a small state machine around WriterFlow's
/// own device-authorization pairing flow (`/v2/device/authorize`,
/// `/v2/device/token`, `/v2/token/refresh`). No MSAL, no
/// `ASWebAuthenticationSession`; the browser step happens outside the app
/// entirely (the website's `/pair` page).
protocol DeviceSessionProviding: Sendable {
    var state: DeviceSessionState { get async }

    /// Starts a new pairing attempt: calls `/v2/device/authorize` and
    /// returns the challenge to show/open. Caller-initiated only — never
    /// call this from a passive typing/focus signal (CLAUDE.md Golden Rule 2).
    func beginPairing() async throws -> PairingChallenge

    /// Polls `/v2/device/token` at the server-advertised interval until
    /// approved, denied, or expired. Resolves once terminal; on success the
    /// tokens are already persisted and `state` is `.signedIn`.
    func awaitPairedToken() async throws

    /// A currently-valid access token, transparently refreshing via the
    /// rotating refresh token if the cached one is expired or near expiry.
    /// Throws (and moves `state` to `.needsRePair`) if refresh fails.
    func accessToken() async throws -> String

    /// Clears the local token cache only. Per V2-ARCHITECTURE.md §5.4,
    /// signing out never touches local history/settings data.
    func signOut() async

    /// Marks the session invalid after the server rejected a cached access
    /// token (e.g. dev-server JWT key rotation). Moves `state` to
    /// `.needsRePair` without deleting the Keychain item.
    func markSessionInvalid() async

    /// Refreshes the access token even when the cached one has not expired.
    /// Used when an authenticated API call returns 401 despite a locally
    /// still-valid expiry.
    func forceRefreshAccessToken() async throws -> String

    /// A foreground hint only (the `writerflow://paired` deep link) — never
    /// call this with anything that could be mistaken for a credential.
    /// Nudges an in-flight poll loop to check sooner; a no-op otherwise.
    func handleForegroundHint() async

    /// Stops an in-flight `awaitPairedToken()` early (e.g. the user closes
    /// the pairing UI) — `awaitPairedToken()` throws `.pairingCancelled` and
    /// `state` returns to `.signedOut`. A no-op if nothing is in flight.
    func cancelPairing() async
}

enum DeviceSessionState: Equatable, Sendable {
    case signedOut
    case pairing(PairingChallenge)
    case signedIn(deviceId: String)
    /// Refresh failed (reuse-detected, revoked, or expired refresh token).
    /// Never a silent sign-out — the UI must show an explicit re-pair action.
    case needsRePair
}

struct PairingChallenge: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL
    let interval: TimeInterval
    let expiresAt: Date
}

enum DeviceSessionError: Error, LocalizedError, Sendable {
    case invalidBaseURL
    case httpError(Int)
    case decodingFailed
    case pairingDenied
    case pairingExpired
    case pairingCancelled
    case notPaired
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "WriterFlow API is not configured correctly."
        case .httpError(let code): return "WriterFlow API request failed (\(code))."
        case .decodingFailed: return "WriterFlow API returned an unexpected response."
        case .pairingDenied: return "Pairing was declined in the browser."
        case .pairingExpired: return "Pairing code expired. Try again."
        case .pairingCancelled: return "Pairing cancelled."
        case .notPaired: return "Sign in required."
        case .refreshFailed: return "Your session expired. Please sign in again."
        }
    }
}

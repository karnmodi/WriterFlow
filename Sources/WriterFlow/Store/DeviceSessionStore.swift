import Foundation

/// Concrete `DeviceSessionProviding` — the pairing state machine, Keychain
/// persistence, and refresh logic described in V2-ARCHITECTURE.md §4.1/§5.1.
/// Never triggers network activity from `init` — every entry point is an
/// explicit call from a user action (CLAUDE.md Golden Rule 2).
actor DeviceSessionStore: DeviceSessionProviding {
    /// Safety margin so a token that's about to expire mid-request still gets refreshed proactively.
    private static let expiryLeeway: TimeInterval = 30

    private let api: WriterFlowAPIClient
    private let installID: String
    private var currentState: DeviceSessionState
    private var pendingChallenge: (challenge: PairingChallenge, verifier: String)?
    private var activeSleepTask: Task<Void, Never>?
    private var cancelRequested = false

    init(api: WriterFlowAPIClient = WriterFlowAPIClient(), installID: String = InstallIdentifier.current) {
        self.api = api
        self.installID = installID
        if let stored = DeviceTokenKeychain.read() {
            self.currentState = .signedIn(deviceId: stored.deviceID)
        } else {
            self.currentState = .signedOut
        }
    }

    var state: DeviceSessionState { currentState }

    func beginPairing() async throws -> PairingChallenge {
        let pkce = PKCE.generate()
        let response = try await api.authorize(installID: installID, deviceLabel: MacHardwareModel.friendlyName, codeChallenge: pkce.challenge)

        guard let verificationURI = URL(string: response.verificationUri),
              let verificationURIComplete = URL(string: response.verificationUriComplete) else {
            throw DeviceSessionError.decodingFailed
        }
        let challenge = PairingChallenge(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURI,
            verificationURIComplete: verificationURIComplete,
            interval: TimeInterval(response.interval),
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        pendingChallenge = (challenge, pkce.verifier)
        currentState = .pairing(challenge)
        Log.auth.info("Device pairing started (user_code shown to user)")
        return challenge
    }

    func awaitPairedToken() async throws {
        guard let (challenge, verifier) = pendingChallenge else {
            throw DeviceSessionError.notPaired
        }
        var interval = challenge.interval
        cancelRequested = false

        while Date() < challenge.expiresAt {
            await sleepOrHint(interval)

            if cancelRequested {
                cancelRequested = false
                pendingChallenge = nil
                currentState = .signedOut
                Log.auth.info("Pairing cancelled")
                throw DeviceSessionError.pairingCancelled
            }

            let result = try await api.pollToken(deviceCode: challenge.deviceCode, codeVerifier: verifier)
            switch result {
            case .issued(let tokens):
                DeviceTokenKeychain.write(
                    .init(
                        deviceID: tokens.deviceId,
                        accessToken: tokens.accessToken,
                        accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)),
                        refreshToken: tokens.refreshToken
                    )
                )
                pendingChallenge = nil
                currentState = .signedIn(deviceId: tokens.deviceId)
                Log.auth.info("Device paired successfully")
                return
            case .pending(let status):
                switch status {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval += 5
                    continue
                case "access_denied":
                    pendingChallenge = nil
                    currentState = .signedOut
                    throw DeviceSessionError.pairingDenied
                case "expired_token":
                    pendingChallenge = nil
                    currentState = .signedOut
                    throw DeviceSessionError.pairingExpired
                default:
                    // Unknown forward-compatible status — keep polling rather than fail hard.
                    continue
                }
            }
        }
        pendingChallenge = nil
        currentState = .signedOut
        throw DeviceSessionError.pairingExpired
    }

    func accessToken() async throws -> String {
        guard let stored = DeviceTokenKeychain.read() else {
            currentState = .signedOut
            throw DeviceSessionError.notPaired
        }
        if stored.accessTokenExpiresAt.timeIntervalSinceNow > Self.expiryLeeway {
            return stored.accessToken
        }

        do {
            let refreshed = try await api.refresh(refreshToken: stored.refreshToken)
            DeviceTokenKeychain.write(
                .init(
                    deviceID: refreshed.deviceId,
                    accessToken: refreshed.accessToken,
                    accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn)),
                    refreshToken: refreshed.refreshToken
                )
            )
            currentState = .signedIn(deviceId: refreshed.deviceId)
            return refreshed.accessToken
        } catch {
            // Never a silent sign-out (V2-ARCHITECTURE.md §5.4) — keep the
            // stale Keychain item so a future explicit re-pair can still see
            // "was signed in as this device"; only .needsRePair changes.
            currentState = .needsRePair
            Log.auth.error("Token refresh failed: \(String(describing: error), privacy: .public)")
            throw DeviceSessionError.refreshFailed
        }
    }

    func signOut() async {
        DeviceTokenKeychain.delete()
        pendingChallenge = nil
        currentState = .signedOut
        Log.auth.info("Signed out")
    }

    func cancelPairing() async {
        guard pendingChallenge != nil else { return }
        cancelRequested = true
        activeSleepTask?.cancel()
    }

    func handleForegroundHint() async {
        // Task.sleep responds to cancellation by throwing, which the `try?`
        // in sleepOrHint below swallows — cancelling is enough to end the
        // wait early. (An earlier version raced a `withCheckedContinuation`
        // against the sleep in a TaskGroup; cancelling that continuation's
        // child task never resumed it, so `withTaskGroup` — which waits for
        // every child task, not just the one `group.next()` returned —
        // deadlocked forever. Plain Task cancellation has no such trap.)
        activeSleepTask?.cancel()
    }

    /// Waits `interval` seconds, but returns early if `handleForegroundHint()`
    /// is called in the meantime — the `writerflow://paired` deep link's only
    /// job (Stage 5.2: "only as a foreground hint to end the polling wait").
    private func sleepOrHint(_ interval: TimeInterval) async {
        let task = Task<Void, Never> {
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            } catch {
                // Cancelled via handleForegroundHint() — that's the point.
            }
        }
        activeSleepTask = task
        await task.value
        if activeSleepTask == task {
            activeSleepTask = nil
        }
    }
}

/// Locally generated opaque install identifier (Docs/contracts/openapi.yaml
/// `DeviceAuthorizeRequest.installId`) — persisted in UserDefaults since it's
/// content-free and not a secret, distinct from the device_id the server
/// assigns after approval.
enum InstallIdentifier {
    private static let defaultsKey = "writerflow.installId"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }
}

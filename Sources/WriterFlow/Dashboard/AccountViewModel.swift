import AppKit
import Foundation

/// Drives the Stage 5.2 Dashboard "Account" card: sign-in (device-authorization
/// pairing), the current device's account snapshot, sign-out, and revoke.
/// Never begins pairing/refresh from `init` or any passive event — every
/// state transition here is the direct result of a user tapping a button in
/// `AccountView` (CLAUDE.md Golden Rule 2).
///
/// Every action below is `async` rather than firing an internal `Task {}` —
/// `AccountView` wraps each button action in its own `Task { await ... }`.
/// That keeps cancellation simple: `cancelSignIn()` calling
/// `session.cancelPairing()` interrupts the in-flight `beginSignIn()` call's
/// suspended `awaitPairedToken()` await via the MainActor's normal
/// cooperative scheduling, with no separate task-handle bookkeeping needed.
@MainActor
final class AccountViewModel: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case signedOut
        case pairing(PairingChallenge)
        case awaitingApproval(PairingChallenge)
        case loaded(WriterFlowAPIClient.AccountSnapshot)
        case needsRePair
        case error(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published var statusMessage: String?
    @Published var statusIsError = false

    private let session: DeviceSessionProviding
    private let accountService: AccountServiceProviding

    init(session: DeviceSessionProviding, accountService: AccountServiceProviding? = nil) {
        self.session = session
        self.accountService = accountService ?? AccountService(session: session)
    }

    /// Reconciles UI state with `DeviceSessionProviding.state` — call on
    /// `AccountView.onAppear` and after any transition that isn't already
    /// self-updating.
    func refresh() async {
        switch await session.state {
        case .signedOut:
            loadState = .signedOut
        case .pairing:
            // A pairing this ViewModel instance didn't start itself (e.g. the
            // app relaunched mid-pairing) — there's no local task tracking it,
            // so the safe move is to let the user start a fresh attempt rather
            // than trying to resume watching someone else's in-flight poll.
            loadState = .signedOut
        case .needsRePair:
            loadState = .needsRePair
        case .signedIn:
            await loadSnapshot()
        }
    }

    private func loadSnapshot() async {
        loadState = .loading
        do {
            let snapshot = try await accountService.fetchSnapshot()
            loadState = .loaded(snapshot)
        } catch DeviceSessionError.refreshFailed, DeviceSessionError.notPaired {
            loadState = .needsRePair
        } catch DeviceSessionError.httpError(401) {
            await session.markSessionInvalid()
            loadState = .needsRePair
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    func beginSignIn() async {
        statusMessage = nil
        do {
            let challenge = try await session.beginPairing()
            loadState = .pairing(challenge)
            openBrowser(for: challenge)
            loadState = .awaitingApproval(challenge)
            try await session.awaitPairedToken()
            if await session.needsRelaunchAfterAccountSwitch {
                statusMessage = "Signed in with a different account. Relaunching so local data stays isolated…"
                statusIsError = false
                relaunchAppForAccountSwitch()
                return
            }
            await loadSnapshot()
        } catch DeviceSessionError.pairingCancelled {
            loadState = .signedOut
        } catch DeviceSessionError.pairingDenied {
            statusMessage = "Sign-in was declined in the browser."
            statusIsError = true
            loadState = .signedOut
        } catch DeviceSessionError.pairingExpired {
            statusMessage = "Sign-in code expired. Try again."
            statusIsError = true
            loadState = .signedOut
        } catch DeviceSessionError.accountMismatch {
            statusMessage = DeviceSessionError.accountMismatch.localizedDescription
            statusIsError = true
            loadState = .signedOut
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            loadState = .signedOut
        }
    }

    /// Re-opens the browser for an in-progress pairing (e.g. the user
    /// dismissed or lost the first popup) — a no-op outside `.awaitingApproval`.
    func reopenBrowser() {
        guard case .awaitingApproval(let challenge) = loadState else { return }
        openBrowser(for: challenge)
    }

    private func openBrowser(for challenge: PairingChallenge) {
        if !NSWorkspace.shared.open(challenge.verificationURIComplete) {
            Log.auth.error("Could not open verification URL in browser")
        }
    }

    private func relaunchAppForAccountSwitch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                Log.auth.error(
                    "Account-switch relaunch failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func cancelSignIn() async {
        await session.cancelPairing()
        loadState = .signedOut
    }

    func signOut() async {
        await session.signOut()
        statusMessage = nil
        loadState = .signedOut
    }

    func revokeDeviceAndSignOut() async {
        do {
            try await accountService.revokeCurrentDeviceAndSignOut()
            statusMessage = "Device revoked and signed out."
            statusIsError = false
        } catch {
            // revokeCurrentDeviceAndSignOut() always signs out locally even
            // on failure (see AccountService) — surface the server-side
            // error but the UI still reflects signed-out.
            statusMessage = "Signed out locally; server revoke may not have completed: \(error.localizedDescription)"
            statusIsError = true
        }
        loadState = .signedOut
    }
}

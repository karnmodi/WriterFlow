import Foundation

/// Stage 5.3 "Store refactor": explicit states for local database startup,
/// replacing the previous silent in-memory fallback on open/migration
/// failure — `WriterFlowDatabase` now reports into this instead of quietly
/// continuing as if nothing happened. The Dashboard observes `state` and
/// shows a banner whenever data isn't actually being persisted, so a disk
/// error is a loud, visible failure (golden rule 7: "never a hang or silent
/// no-op"), not silent data loss the user only discovers later.
///
/// `.locked` and `.migrationRequired` are forward declarations for the
/// not-yet-built pieces of this same checklist section — SQLCipher
/// encryption keyed via `DatabaseKeychain` and the V1 atomic migration.
/// Neither is reachable yet: `WriterFlowDatabase` still opens the same plain
/// (unencrypted) v1 SQLite file it always has, so there is nothing to
/// unlock and no migration to require. They exist now so the state type
/// doesn't need a breaking change when that work lands.
@MainActor
final class LaunchCoordinator: ObservableObject {
    static let shared = LaunchCoordinator()

    enum State: Equatable {
        case opening
        case ready
        case locked
        case migrationRequired
        case recoveryRequired(String)
        case failed(String)
    }

    @Published private(set) var state: State = .opening

    private init() {}

    /// Called once by `WriterFlowDatabase.shared`'s init closure. Not public
    /// API beyond that one call site — everything else should only read
    /// `state`.
    func reportReady() {
        state = .ready
    }

    func reportFailure(_ message: String) {
        state = .failed(message)
    }
}

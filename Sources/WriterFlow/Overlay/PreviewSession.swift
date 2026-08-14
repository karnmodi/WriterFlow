import Foundation

/// Pure helpers for soft-hide vs hard-clear of an in-flight / completed-unseen preview.
/// Kept free of AppKit so XCTest can cover the dismiss policy.
enum PreviewSession {
    /// True while a run is streaming, clarifying, or holding a result/error the user
    /// has not accepted or permanently discarded.
    static func hasActiveSession(
        pendingAction: WritingAction?,
        isStreaming: Bool,
        hasVisibleText: Bool,
        hasError: Bool,
        isClarify: Bool
    ) -> Bool {
        guard pendingAction != nil else { return false }
        return isStreaming || hasVisibleText || hasError || isClarify
    }

    /// Esc / Close / field blur while recoverable work is active → soft-hide.
    /// Terminal failures hard-clear so the normal floating icon returns (no busy spinner).
    static func shouldSoftHideOnDismiss(
        hasActiveSession: Bool,
        isStreaming: Bool,
        hasVisibleText: Bool,
        hasError: Bool,
        isClarify: Bool
    ) -> Bool {
        guard hasActiveSession else { return false }
        if hasError && !isStreaming {
            return false
        }
        return isStreaming || hasVisibleText || isClarify
    }

    /// Floating icon stays busy while streaming or while a soft-hidden recoverable
    /// session awaits reopen — never for a finished error state.
    static func isIconBusy(
        isStreaming: Bool,
        isSoftHidden: Bool,
        hasActiveSession: Bool,
        hasError: Bool
    ) -> Bool {
        if hasError && !isStreaming {
            return false
        }
        return isStreaming || (isSoftHidden && hasActiveSession)
    }

    /// After finish/fail, auto-restore a soft-hidden card so the user sees the outcome.
    static func shouldAutoRestoreOnCompletion(isSoftHidden: Bool, hasActiveSession: Bool) -> Bool {
        isSoftHidden && hasActiveSession
    }
}

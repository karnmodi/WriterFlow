import Foundation

/// Temporary delegate used before the real OverlayController lands in Phase 0.4.
/// Emits os_log lines so the Phase 0.3 acceptance criteria are verifiable.
@MainActor
final class LoggingFocusDelegate: FocusMonitorDelegate {
    func focusMonitor(_ monitor: FocusMonitor, fieldDidFocus field: FocusedField) {
        Log.focus.info(
            "fieldFocused role=\(field.role, privacy: .public) app=\(field.appBundleID ?? "?", privacy: .public) frame=\(String(describing: field.frame), privacy: .public)"
        )
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldDidBlur previousBundleID: String?) {
        Log.focus.info("fieldBlurred app=\(previousBundleID ?? "?", privacy: .public)")
    }

    func focusMonitorTypingStarted(_ monitor: FocusMonitor) {
        Log.focus.info("typingStarted")
    }

    func focusMonitorTypingStopped(_ monitor: FocusMonitor) {
        Log.focus.info("typingStopped")
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated frame: CGRect) {
        Log.focus.debug("frameUpdated frame=\(String(describing: frame), privacy: .public)")
    }
}

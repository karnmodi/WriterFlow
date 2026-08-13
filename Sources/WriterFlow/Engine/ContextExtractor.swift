import ApplicationServices
import Foundation

enum ContextExtractor {
    /// Read the currently focused field of the given process.
    /// Runs off-main and returns `nil` if nothing focused / not text-editable.
    static func readFocusedField(pid: pid_t, bundleID: String?) async -> FieldSnapshot? {
        if let outcome = await readOnce(pid: pid, bundleID: bundleID) {
            logSnapshot(outcome.snapshot)
            if !outcome.snapshot.fullText.isEmpty || !outcome.snapshot.selectedText.isEmpty {
                recordRead(bundleID, ok: true)
                return outcome.snapshot
            }
            if outcome.valueUnreadable, let fallback = await copyAllFallback(pid: pid, base: outcome.snapshot) {
                recordRead(bundleID, ok: true)
                return fallback
            }
            // AX value can lag behind keystroke bootstrap — retry once.
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let retry = await readOnce(pid: pid, bundleID: bundleID) {
                logSnapshot(retry.snapshot)
                recordRead(bundleID, ok: true)
                return retry.snapshot
            }
            recordRead(bundleID, ok: false)
            return outcome.snapshot
        }
        recordRead(bundleID, ok: false)
        return nil
    }

    private static func recordRead(_ bundleID: String?, ok: Bool) {
        Task { await CompatibilityMap.shared.recordRead(bundleID: bundleID, ok: ok) }
        Task { @MainActor in AXWatchdog.shared.record(bundleID: bundleID, ok: ok) }
    }

    private struct ReadOutcome {
        let snapshot: FieldSnapshot
        /// True when `kAXValue` itself couldn't be read at all (vs. legitimately empty) —
        /// the case the Stage 4.1 clipboard read-fallback (⌘A ⌘C) exists for.
        let valueUnreadable: Bool
    }

    private static func readOnce(pid: pid_t, bundleID: String?) async -> ReadOutcome? {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                let outcome = readSync(pid: pid, bundleID: bundleID)
                continuation.resume(returning: outcome)
            }
        }
    }

    private static func readSync(pid: pid_t, bundleID: String?) -> ReadOutcome? {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let rawFocused = FocusedElementResolver.focusedElement(in: app),
              let focused = FocusedElementResolver.resolveEditable(
                from: rawFocused,
                bundleID: bundleID
              ),
              let role = AXCall.string(focused, AXAttr.role)
        else { return nil }

        let rawValue = AXCall.string(focused, AXAttr.value)
        let rawText = rawValue ?? ""
        let windowTitle = focusedWindowTitle(app: app)
        let isTerminal = TerminalApps.isTerminal(bundleID: bundleID)

        // Terminals expose the whole scrollback as one blob with no meaningful
        // selection — reduce to just the current input line. Replace uses
        // TerminalLineInserter (Ctrl+U + paste), never AX scrollback write / ⌘A.
        if isTerminal {
            let line = TerminalApps.currentLine(from: rawText)
            let snapshot = FieldSnapshot(
                fullText: line,
                selectedText: "",
                selectedRange: NSRange(location: 0, length: (line as NSString).length),
                role: role,
                appBundleID: bundleID,
                windowTitle: windowTitle,
                supportsReplace: true
            )
            return ReadOutcome(snapshot: snapshot, valueUnreadable: false)
        }

        let selectedText = AXCall.string(focused, AXAttr.selectedText) ?? ""
        let range = AXCall.range(focused, AXAttr.selectedTextRange)
            ?? NSRange(location: 0, length: (rawText as NSString).length)

        let snapshot = FieldSnapshot(
            fullText: rawText,
            selectedText: selectedText,
            selectedRange: range,
            role: role,
            appBundleID: bundleID,
            windowTitle: windowTitle
        )
        return ReadOutcome(snapshot: snapshot, valueUnreadable: rawValue == nil)
    }

    /// Stage 4.1 read fallback: ⌘A ⌘C via `ClipboardWriter`, restoring the prior selection
    /// and the user's clipboard afterward. Only reached when `kAXValue` was structurally
    /// unreadable (not merely empty) on a non-terminal field.
    private static func copyAllFallback(pid: pid_t, base: FieldSnapshot) async -> FieldSnapshot? {
        guard let copied = await MainActor.run(body: { ClipboardWriter.executeCopyAll(pid: pid) }),
              !copied.isEmpty
        else { return nil }
        Log.engine.info("ContextExtractor: recovered \(copied.count, privacy: .public) chars via clipboard read-fallback")
        return FieldSnapshot(
            fullText: copied,
            selectedText: "",
            selectedRange: NSRange(location: 0, length: (copied as NSString).length),
            role: base.role,
            appBundleID: base.appBundleID,
            windowTitle: base.windowTitle,
            supportsReplace: base.supportsReplace
        )
    }

    private static func focusedWindowTitle(app: AXUIElement) -> String? {
        guard let window = AXCall.element(app, AXAttr.focusedWindow) else { return nil }
        return AXCall.string(window, AXAttr.title)
    }

    private static func logSnapshot(_ snapshot: FieldSnapshot) {
        Log.engine.debug(
            "ContextExtractor role=\(snapshot.role, privacy: .public) full=\(snapshot.fullText.count, privacy: .public) selected=\(snapshot.selectedText.count, privacy: .public)"
        )
    }
}

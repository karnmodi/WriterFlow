import ApplicationServices
import Foundation

enum ContextExtractor {
    /// Read the currently focused field of the given process.
    /// Runs off-main and returns `nil` if nothing focused / not text-editable.
    static func readFocusedField(pid: pid_t, bundleID: String?) async -> FieldSnapshot? {
        if let snapshot = await readOnce(pid: pid, bundleID: bundleID) {
            logSnapshot(snapshot)
            if !snapshot.fullText.isEmpty || !snapshot.selectedText.isEmpty {
                return snapshot
            }
            // AX value can lag behind keystroke bootstrap — retry once.
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let retry = await readOnce(pid: pid, bundleID: bundleID) {
                logSnapshot(retry)
                return retry
            }
            return snapshot
        }
        return nil
    }

    private static func readOnce(pid: pid_t, bundleID: String?) async -> FieldSnapshot? {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                let snapshot = readSync(pid: pid, bundleID: bundleID)
                continuation.resume(returning: snapshot)
            }
        }
    }

    private static func readSync(pid: pid_t, bundleID: String?) -> FieldSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let rawFocused = FocusedElementResolver.focusedElement(in: app),
              let focused = FocusedElementResolver.resolveEditable(from: rawFocused),
              let role = AXCall.string(focused, AXAttr.role)
        else { return nil }

        let fullText = AXCall.string(focused, AXAttr.value) ?? ""
        let selectedText = AXCall.string(focused, AXAttr.selectedText) ?? ""
        let range = AXCall.range(focused, AXAttr.selectedTextRange)
            ?? NSRange(location: 0, length: (fullText as NSString).length)

        return FieldSnapshot(
            fullText: fullText,
            selectedText: selectedText,
            selectedRange: range,
            role: role,
            appBundleID: bundleID
        )
    }

    private static func logSnapshot(_ snapshot: FieldSnapshot) {
        Log.engine.debug(
            "ContextExtractor role=\(snapshot.role, privacy: .public) full=\(snapshot.fullText.count, privacy: .public) selected=\(snapshot.selectedText.count, privacy: .public)"
        )
    }
}

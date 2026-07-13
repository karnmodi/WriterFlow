import ApplicationServices
import Foundation

enum ContextExtractor {
    /// Read the currently focused field of the given process.
    /// Runs off-main and returns `nil` if nothing focused / not text-editable.
    static func readFocusedField(pid: pid_t, bundleID: String?) async -> FieldSnapshot? {
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
        guard let focused = AXCall.element(app, AXAttr.focusedUIElement) else { return nil }
        guard let role = AXCall.string(focused, AXAttr.role) else { return nil }

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
}

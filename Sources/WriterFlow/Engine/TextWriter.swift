import ApplicationServices
import Foundation

enum TextWriter {
    /// Write `replacement` into the focused field.
    ///
    /// Tiered strategy per Phase 1.1:
    ///   1. Selected-range replacement (preserves rich text).
    ///   2. Full `AXValue` overwrite (plain fields only — destroys rich formatting).
    ///   3. Clipboard fallback lands in Phase 4.
    static func replace(
        pid: pid_t,
        range: NSRange,
        with replacement: String
    ) async -> WriteResult {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                let result = replaceSync(pid: pid, range: range, with: replacement)
                continuation.resume(returning: result)
            }
        }
    }

    private static func replaceSync(pid: pid_t, range: NSRange, with replacement: String) -> WriteResult {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let focused = AXCall.element(app, AXAttr.focusedUIElement) else {
            return .failed("No focused element")
        }

        // Tier 1: selection replacement.
        if AXCall.setRange(focused, AXAttr.selectedTextRange, range: range),
           AXCall.setString(focused, AXAttr.selectedText, value: replacement) {
            return .selectedTextReplaced
        }

        // Tier 2: gated by role — full-value overwrite is only acceptable for plain fields.
        let role = AXCall.string(focused, AXAttr.role) ?? ""
        let plainRoles: Set<String> = [AXRole.textField, AXRole.textArea, AXRole.comboBox]
        if plainRoles.contains(role) {
            let currentText = AXCall.string(focused, AXAttr.value) ?? ""
            let nsCurrent = currentText as NSString
            let safeRange = clampRange(range, in: nsCurrent.length)
            let newText = nsCurrent.replacingCharacters(in: safeRange, with: replacement)
            if AXCall.setString(focused, AXAttr.value, value: newText) {
                return .fullValueReplaced
            }
        }

        return .failed("AX write refused")
    }

    private static func clampRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let remaining = length - location
        return NSRange(location: location, length: max(0, min(range.length, remaining)))
    }
}

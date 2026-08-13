import ApplicationServices
import CoreGraphics
import Foundation

/// Shared AX focus resolution — window-first lookup, editable ancestor walk,
/// and compose-scoped child search for web/Electron editors (Gmail, Cursor, VS Code).
enum FocusedElementResolver {
    private static let maxAncestorDepth = 10
    private static let maxChildDepth = 4
    private static let maxWebChildDepth = 12
    private static let maxComposeTextLength = 8_192
    /// Docs surfaces can hold much longer drafts; still cap to keep candidate ranking sane.
    private static let maxDocumentTextLength = 100_000

    /// Focused element for an app — prefers the focused window (Notes, browsers).
    static func focusedElement(in app: AXUIElement) -> AXUIElement? {
        if let window = AXCall.element(app, AXAttr.focusedWindow),
           let focused = AXCall.element(window, AXAttr.focusedUIElement) {
            return focused
        }
        return AXCall.element(app, AXAttr.focusedUIElement)
    }

    /// Map a raw focused AX node to the editable field WriterFlow should target.
    static func resolveEditable(
        from element: AXUIElement,
        bundleID: String? = nil,
        windowTitle: String? = nil
    ) -> AXUIElement? {
        let policy = ComposeAppPolicy.resolve(bundleID: bundleID, windowTitle: windowTitle)

        if policy == .spreadsheet {
            return resolveSpreadsheetEditable(from: element)
        }

        if let scoped = resolveScopedComposeField(
            preferredRoot: element,
            rawFocused: element,
            policy: policy
        ) {
            return scoped
        }

        var current = AXCall.element(element, AXAttr.parent)
        for _ in 0..<maxAncestorDepth {
            guard let node = current else { break }
            if let scoped = resolveScopedComposeField(
                preferredRoot: node,
                rawFocused: element,
                policy: policy
            ) {
                return scoped
            }
            current = AXCall.element(node, AXAttr.parent)
        }
        return nil
    }

    // MARK: - Spreadsheet (Excel / Numbers)

    private static func resolveSpreadsheetEditable(from element: AXUIElement) -> AXUIElement? {
        // Prefer the formula bar / native text field when focused.
        if FocusedFieldClassifier.isEditableElement(element),
           let role = AXCall.string(element, AXAttr.role),
           role == AXRole.textField || role == AXRole.textArea || role == AXRole.comboBox {
            return element
        }

        var current: AXUIElement? = element
        for _ in 0..<maxAncestorDepth {
            guard let node = current else { break }
            if FocusedFieldClassifier.isEditableElement(node),
               let role = AXCall.string(node, AXAttr.role),
               role == AXRole.textField || role == AXRole.textArea {
                return node
            }
            current = AXCall.element(node, AXAttr.parent)
        }

        // Fall back to a small writable cell — never a huge sheet container.
        if FocusedFieldClassifier.isEditableElement(element),
           isReasonableComposeCandidate(element, policy: .spreadsheet) {
            return element
        }
        return nil
    }

    // MARK: - Compose scoping (Gmail web areas, Cursor, Docs)

    private static func resolveScopedComposeField(
        preferredRoot: AXUIElement,
        rawFocused: AXUIElement,
        policy: ComposeAppPolicy
    ) -> AXUIElement? {
        let role = AXCall.string(preferredRoot, AXAttr.role) ?? ""
        let textLen = (AXCall.string(preferredRoot, AXAttr.value) ?? "").count
        let maxText = policy == .documentSurface ? maxDocumentTextLength : maxComposeTextLength

        // Direct focus on a non-web field — use it immediately (search bars, list inputs).
        if FocusedFieldClassifier.isEditableElement(preferredRoot),
           role != AXRole.webArea,
           textLen <= maxText {
            if policy == .documentSurface || isReasonableComposeCandidate(preferredRoot, policy: policy) {
                return preferredRoot
            }
        }

        // Huge web area or oversized value — find the innermost compose descendant.
        let needsDescendantSearch = role == AXRole.webArea
            || textLen > maxComposeTextLength
            || policy == .documentSurface
        guard needsDescendantSearch else {
            return FocusedFieldClassifier.isEditableElement(preferredRoot) ? preferredRoot : nil
        }

        var candidates: [AXUIElement] = []
        if FocusedFieldClassifier.isEditableElement(preferredRoot) {
            candidates.append(preferredRoot)
        }
        collectEditableDescendants(
            of: preferredRoot,
            depth: 0,
            maxDepth: maxWebChildDepth,
            into: &candidates
        )

        guard !candidates.isEmpty else { return nil }

        let reasonable = candidates.filter { isReasonableComposeCandidate($0, policy: policy) }
        guard !reasonable.isEmpty else { return nil }
        return reasonable.min(by: { candidateRank($0, prefer: rawFocused) < candidateRank($1, prefer: rawFocused) })
    }

    private static func collectEditableDescendants(
        of element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        into out: inout [AXUIElement]
    ) {
        guard depth < maxDepth else { return }
        for child in AXCall.children(element) {
            if FocusedFieldClassifier.isEditableElement(child) {
                out.append(child)
            }
            collectEditableDescendants(of: child, depth: depth + 1, maxDepth: maxDepth, into: &out)
        }
    }

    private static func isReasonableComposeCandidate(
        _ element: AXUIElement,
        policy: ComposeAppPolicy
    ) -> Bool {
        guard let frame = AXCall.axFrame(element) else { return false }
        guard frame.width > 20 && frame.height > 8 else { return false }

        let textLen = (AXCall.string(element, AXAttr.value) ?? "").count
        let maxText = policy == .documentSurface ? maxDocumentTextLength : maxComposeTextLength
        if textLen > maxText { return false }

        if policy == .documentSurface {
            // Prefer writable focused editors; reject absurd multi-monitor widths.
            if frame.width >= 8_000 { return false }
            let canWrite = AXCall.isSettable(element, AXAttr.selectedTextRange)
                || AXCall.isSettable(element, AXAttr.value)
            return canWrite || FocusedFieldClassifier.isEditableElement(element)
        }

        if let maxWidth = policy.maxWebWidth, frame.width > maxWidth { return false }
        if let maxHeight = policy.maxWebHeight, frame.height > maxHeight { return false }
        if frame.width >= 5_000 { return false }
        return true
    }

    private static func candidateRank(
        _ element: AXUIElement,
        prefer rawFocused: AXUIElement
    ) -> (Int, CGFloat, Int) {
        let isPreferred = CFEqual(element, rawFocused) ? 0 : 1
        let frame = AXCall.axFrame(element) ?? CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let area = max(frame.width, 1) * max(frame.height, 1)
        let textLen = (AXCall.string(element, AXAttr.value) ?? "").count
        return (isPreferred, area, textLen)
    }
}

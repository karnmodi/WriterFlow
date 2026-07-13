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

    /// Focused element for an app — prefers the focused window (Notes, browsers).
    static func focusedElement(in app: AXUIElement) -> AXUIElement? {
        if let window = AXCall.element(app, AXAttr.focusedWindow),
           let focused = AXCall.element(window, AXAttr.focusedUIElement) {
            return focused
        }
        return AXCall.element(app, AXAttr.focusedUIElement)
    }

    /// Map a raw focused AX node to the editable field WriterFlow should target.
    static func resolveEditable(from element: AXUIElement) -> AXUIElement? {
        if let scoped = resolveScopedComposeField(preferredRoot: element, rawFocused: element) {
            return scoped
        }

        var current = AXCall.element(element, AXAttr.parent)
        for _ in 0..<maxAncestorDepth {
            guard let node = current else { break }
            if let scoped = resolveScopedComposeField(preferredRoot: node, rawFocused: element) {
                return scoped
            }
            current = AXCall.element(node, AXAttr.parent)
        }
        return nil
    }

    // MARK: - Compose scoping (Gmail web areas)

    private static func resolveScopedComposeField(
        preferredRoot: AXUIElement,
        rawFocused: AXUIElement
    ) -> AXUIElement? {
        let role = AXCall.string(preferredRoot, AXAttr.role) ?? ""
        let textLen = (AXCall.string(preferredRoot, AXAttr.value) ?? "").count

        // Direct focus on a non-web field — use it immediately (search bars, list inputs).
        if FocusedFieldClassifier.isEditableElement(preferredRoot),
           role != AXRole.webArea,
           textLen <= maxComposeTextLength {
            return preferredRoot
        }

        // Huge web area or oversized value — find the innermost compose descendant.
        let needsDescendantSearch = role == AXRole.webArea || textLen > maxComposeTextLength
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

        let reasonable = candidates.filter { isReasonableComposeCandidate($0, inWebContext: true) }
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
        inWebContext: Bool
    ) -> Bool {
        guard let frame = AXCall.axFrame(element) else { return false }
        guard frame.width > 20 && frame.height > 8 else { return false }
        if inWebContext {
            let textLen = (AXCall.string(element, AXAttr.value) ?? "").count
            if textLen > maxComposeTextLength { return false }
            if frame.width >= 5_000 { return false }
            if frame.width > 1_200 || frame.height > 600 { return false }
        }
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

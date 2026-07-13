import ApplicationServices
import Foundation

/// AX tree walk that collects visible conversation-like text (Gmail thread,
/// WhatsApp/Slack chat) above the focused field. Per Stage 2.2's privacy rule,
/// full content (`extractConversation`) is only ever called from Reply/Custom —
/// never passively. `hasVisibleConversation` is a structural presence check
/// with no content, safe for the Recommendation Engine to call on every popover open.
enum ConversationExtractor {
    private static let maxChars = 4_000
    private static let cacheTTL: TimeInterval = 10
    private static let noiseDenylist: Set<String> = ["reply", "forward", "react", "like", "share", "more", "...", "reply all"]

    /// Full conversation text, most-recent-last, capped at 4,000 chars. Reply/Custom only.
    /// `excludingDraft` omits the compose-field text so the model sees the thread, not a paraphrase target.
    static func extractConversation(pid: pid_t, excludingDraft draft: String? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: extractSync(pid: pid, excludingDraft: draft))
            }
        }
    }

    /// Cheap structural check — no message content is read into memory beyond
    /// what's needed to confirm presence. Safe to call on every popover open.
    static func hasVisibleConversation(pid: pid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: hasConversationSync(pid: pid))
            }
        }
    }

    // MARK: - Sync (AXQueue only)

    private static func extractSync(pid: pid_t, excludingDraft draft: String?) -> String? {
        let cacheKey = cacheKey(pid: pid, draft: draft)
        if let cached = cacheGet(cacheKey) { return cached }

        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let window = AXCall.element(app, AXAttr.focusedWindow),
              let windowFrame = AXCall.axFrame(window)
        else { return nil }

        let composeContext = composeContext(in: app)
        let nodes = collectTextNodes(
            from: window,
            windowFrame: windowFrame,
            composeFrame: composeContext?.frame,
            composeElement: composeContext?.element,
            excludingDraft: draft,
            limit: 200
        )
        guard !nodes.isEmpty else { return nil }

        let deduped = dedupeAdjacent(nodes)
        let capped = capKeepingRecent(deduped.joined(separator: "\n"))
        cacheSet(cacheKey, text: capped)
        return capped.isEmpty ? nil : capped
    }

    private static func hasConversationSync(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let window = AXCall.element(app, AXAttr.focusedWindow),
              let windowFrame = AXCall.axFrame(window)
        else { return false }

        let composeContext = composeContext(in: app)
        return collectTextNodes(
            from: window,
            windowFrame: windowFrame,
            composeFrame: composeContext?.frame,
            composeElement: composeContext?.element,
            excludingDraft: nil,
            limit: 2
        ).count >= 2
    }

    private struct ComposeContext {
        let element: AXUIElement
        let frame: CGRect
    }

    private static func composeContext(in app: AXUIElement) -> ComposeContext? {
        guard let rawFocused = FocusedElementResolver.focusedElement(in: app),
              let editable = FocusedElementResolver.resolveEditable(from: rawFocused),
              let frame = AXCall.axFrame(editable)
        else { return nil }
        return ComposeContext(element: editable, frame: frame)
    }

    private static func collectTextNodes(
        from root: AXUIElement,
        windowFrame: CGRect,
        composeFrame: CGRect?,
        composeElement: AXUIElement?,
        excludingDraft draft: String?,
        limit: Int
    ) -> [String] {
        let normalizedDraft = draft.map(normalizeForComparison)
        var queue: [AXUIElement] = [root]
        var results: [(y: CGFloat, text: String)] = []
        var visited = 0
        let maxVisited = 2_000

        while !queue.isEmpty, results.count < limit, visited < maxVisited {
            let element = queue.removeFirst()
            visited += 1

            if let composeElement, CFEqual(element, composeElement) {
                queue.append(contentsOf: AXCall.children(element))
                continue
            }

            if let role = AXCall.string(element, AXAttr.role),
               role == AXRole.staticText || role == AXRole.textArea,
               let frame = AXCall.axFrame(element), frame.intersects(windowFrame),
               let text = AXCall.string(element, AXAttr.value), isSignal(text) {
                if shouldExclude(
                    text: text,
                    role: role,
                    frame: frame,
                    composeFrame: composeFrame,
                    normalizedDraft: normalizedDraft
                ) {
                    queue.append(contentsOf: AXCall.children(element))
                    continue
                }
                results.append((y: frame.origin.y, text: text))
            }

            queue.append(contentsOf: AXCall.children(element))
        }

        // AX y is top-left-origin, growing downward — ascending y is top-to-bottom.
        return results.sorted { $0.y < $1.y }.map(\.text)
    }

    private static func shouldExclude(
        text: String,
        role: String,
        frame: CGRect,
        composeFrame: CGRect?,
        normalizedDraft: String?
    ) -> Bool {
        if let normalizedDraft, !normalizedDraft.isEmpty {
            let normalizedText = normalizeForComparison(text)
            if normalizedText == normalizedDraft { return true }
            if normalizedText.contains(normalizedDraft), normalizedDraft.count > 20 { return true }
        }

        guard let composeFrame else { return false }

        // Compose box sits at the bottom — skip editable nodes overlapping it.
        if role == AXRole.textArea, framesOverlap(frame, composeFrame) { return true }

        // Skip nodes clearly below the top of the compose area (sidebar noise excepted via isSignal).
        if role == AXRole.textArea, frame.minY >= composeFrame.minY - 8 { return true }

        return false
    }

    private static func framesOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.intersects(b) && a.width > 40 && a.height > 8
    }

    private static func normalizeForComparison(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func dedupeAdjacent(_ lines: [String]) -> [String] {
        var out: [String] = []
        for line in lines {
            if out.last != line { out.append(line) }
        }
        return out
    }

    private static func isSignal(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return false }
        if noiseDenylist.contains(trimmed.lowercased()) { return false }
        if trimmed.allSatisfy({ $0.isNumber || $0 == ":" || $0.isWhitespace }) { return false }
        return true
    }

    private static func capKeepingRecent(_ text: String) -> String {
        guard text.count > maxChars else { return text }
        return String(text.suffix(maxChars))
    }

    private static func cacheKey(pid: pid_t, draft: String?) -> String {
        let draftKey = draft.map(normalizeForComparison) ?? ""
        return "\(pid)|\(draftKey)"
    }

    // MARK: - Cache (AXQueue-confined, so a plain dictionary is safe)

    nonisolated(unsafe) private static var cacheStore: [String: (text: String, expires: Date)] = [:]

    private static func cacheGet(_ key: String) -> String? {
        guard let entry = cacheStore[key], entry.expires > Date() else { return nil }
        return entry.text
    }

    private static func cacheSet(_ key: String, text: String) {
        cacheStore[key] = (text, Date().addingTimeInterval(cacheTTL))
    }
}

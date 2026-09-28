import Foundation
import NaturalLanguage

/// Phase 6 Stage 6.2 — privacy-bounded context signals for classifier routing.
/// Only populated after explicit user action (icon click / hotkey); never from passive key buffering.
struct ContextSignalBuilder: Sendable {
    struct Signals: Sendable, Equatable {
        let bundleId: String
        let site: String?
        let windowClass: String?
        let targetScope: String
        let hasSelection: Bool
        let hasVisibleThread: Bool
        let draftLength: Int
        let appCategory: String
        let destinationKind: String
        let composeSurface: String
        let draftState: String
        let contentShape: String
        let constraintCount: Int
        let appTone: String
        let languageHint: String?
    }

    static func build(snapshot: FieldSnapshot, conversationContext: String?) -> Signals {
        let site = AppAdapterRegistry.siteLabel(bundleID: snapshot.appBundleID, windowTitle: snapshot.windowTitle)
        let hasThread = !(conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSelection = !snapshot.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Signals(
            bundleId: snapshot.appBundleID ?? "unknown",
            site: site,
            windowClass: snapshot.windowTitle,
            targetScope: hasSelection ? "selection" : "field",
            hasSelection: hasSelection,
            hasVisibleThread: hasThread,
            draftLength: snapshot.actionText.count,
            appCategory: appCategory(site: site),
            destinationKind: destinationKind(site: site, hasThread: hasThread),
            composeSurface: composeSurface(hasThread: hasThread),
            draftState: draftState(text: snapshot.actionText),
            contentShape: contentShape(text: snapshot.actionText, site: site),
            constraintCount: constraintCount(text: snapshot.actionText),
            appTone: appTone(site: site),
            languageHint: languageHint(text: snapshot.actionText)
        )
    }

    static func appCategory(site: String?) -> String {
        switch site?.lowercased() {
        case "gmail", "outlook", "mail.google.com": return "email"
        case "whatsapp-web", "whatsapp-desktop", "telegram": return "personal_message"
        case "slack", "teams": return "work_message"
        case "chatgpt", "claude", "gemini", "copilot", "perplexity": return "llm_chat"
        case "cursor": return "code"
        default: return "other"
        }
    }

    static func destinationKind(site: String?, hasThread: Bool) -> String {
        let category = appCategory(site: site)
        if category == "llm_chat" { return "prompt" }
        if category == "code" { return "code" }
        if hasThread { return "reply" }
        if category == "email" || category == "personal_message" || category == "work_message" {
            return "compose"
        }
        return "document"
    }

    static func composeSurface(hasThread: Bool) -> String {
        hasThread ? "thread_reply" : "editor"
    }

    static func draftState(text: String) -> String {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count == 0 { return "empty" }
        return count < 80 ? "fragment" : "substantial"
    }

    static func contentShape(text: String, site: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }
        if appCategory(site: site) == "code" { return "code" }
        if trimmed.contains("\n- ") || trimmed.contains("\n• ") { return "list" }
        if trimmed.contains("\n") { return "paragraph" }
        return trimmed.count < 180 ? "sentence" : "paragraph"
    }

    static func constraintCount(text: String) -> Int {
        let lower = text.lowercased()
        let markers = ["must", "should", "do not", "don't", "keep", "include", "exclude", "without", "exactly"]
        return min(32, markers.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) })
    }

    static func appTone(site: String?) -> String {
        switch site?.lowercased() {
        case "gmail", "outlook", "linkedin": return "formal"
        case "slack", "whatsapp-web", "whatsapp-desktop", "telegram": return "casual"
        default: return "neutral"
        }
    }

    static func languageHint(text: String) -> String? {
        let bounded = String(text.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard bounded.count >= 12 else { return nil }
        return NLLanguageRecognizer.dominantLanguage(for: bounded)?.rawValue
    }
}

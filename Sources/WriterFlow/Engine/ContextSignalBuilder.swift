import Foundation

/// Phase 6 Stage 6.2 — privacy-bounded context signals for classifier routing.
/// Only populated after explicit user action (icon click / hotkey); never from passive key buffering.
struct ContextSignalBuilder: Sendable {
    struct Signals: Sendable {
        let bundleId: String
        let site: String?
        let windowClass: String?
        let targetScope: String
        let hasSelection: Bool
        let hasVisibleThread: Bool
        let draftLength: Int
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
            draftLength: snapshot.actionText.count
        )
    }
}

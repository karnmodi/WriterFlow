import AppKit

/// A borderless, non-activating NSPanel that never becomes key or main —
/// so clicking the icon can never steal focus from the user's text field.
final class FloatingPanel: NSPanel {
    /// Scoped exception for Custom prompt text entry (Phase 2.4) — false for
    /// every panel except while the action popover's text field is focused.
    /// Never touched by the icon or preview panels, which stay permanently non-key.
    var allowsKeyWhenNeeded: Bool = false

    init(size: CGSize, level: NSWindow.Level = .floating) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        self.level = level
        // Do NOT use `.transient` — macOS auto-orders those out when WriterFlow is not
        // the frontmost app, which is exactly when the floating icon must stay visible
        // over Notes/Slack/etc. `.ignoresCycle` keeps ⌘` from landing on the overlay.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        worksWhenModal = true
        isMovable = false
        isMovableByWindowBackground = false
        // Never accept keyboard focus.
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { allowsKeyWhenNeeded }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { allowsKeyWhenNeeded }
}

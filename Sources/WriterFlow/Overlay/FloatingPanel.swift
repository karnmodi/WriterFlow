import AppKit

/// A borderless, non-activating NSPanel that never becomes key or main —
/// so clicking the icon can never steal focus from the user's text field.
final class FloatingPanel: NSPanel {
    init(size: CGSize, level: NSWindow.Level = .floating) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

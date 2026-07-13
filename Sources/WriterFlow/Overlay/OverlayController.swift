import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: FloatingPanel
    private var currentField: FocusedField?
    private var isVisible: Bool = false

    /// Called when the user clicks the icon or the popover requests to open.
    /// Phase 0.4 → placeholder; Phase 1.2 will replace with the real popover.
    var onIconClicked: (() -> Void)?

    private let iconSize = CGSize(width: 28, height: 28)
    private let fieldPadding: CGFloat = 4

    init() {
        self.panel = FloatingPanel(size: iconSize)
        panel.contentView = NSHostingView(rootView: FloatingIconView(onClick: {}))
        panel.alphaValue = 0
        rewireHosting()
    }

    private func rewireHosting() {
        let hosting = NSHostingView(rootView: FloatingIconView { [weak self] in
            self?.handleIconClick()
        })
        hosting.frame = NSRect(origin: .zero, size: iconSize)
        panel.contentView = hosting
    }

    // MARK: - FocusMonitor events

    func fieldDidFocus(_ field: FocusedField) {
        currentField = field
    }

    func fieldDidBlur() {
        currentField = nil
        hide()
    }

    func typingStarted() {
        guard let field = currentField else { return }
        position(near: field.frame)
        show()
    }

    func typingStopped() {
        hide()
    }

    func fieldFrameUpdated(_ frame: CGRect) {
        currentField = currentField.map {
            FocusedField(role: $0.role, frame: frame, appBundleID: $0.appBundleID, appPID: $0.appPID)
        }
        if isVisible { position(near: frame) }
    }

    // MARK: - Positioning

    private func position(near fieldFrame: CGRect) {
        let anchorX = fieldFrame.maxX - iconSize.width - fieldPadding
        let anchorY = fieldFrame.minY + fieldPadding
        var origin = CGPoint(x: anchorX, y: anchorY)
        origin = clampToScreen(origin: origin)
        panel.setFrameOrigin(origin)
    }

    private func clampToScreen(origin: CGPoint) -> CGPoint {
        let iconRect = CGRect(origin: origin, size: iconSize)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(iconRect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        var out = origin
        out.x = min(max(out.x, visible.minX + 2), visible.maxX - iconSize.width - 2)
        out.y = min(max(out.y, visible.minY + 2), visible.maxY - iconSize.height - 2)
        return out
    }

    // MARK: - Show/hide with 120 ms fade

    private func show() {
        guard !isVisible else { return }
        isVisible = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    // MARK: - Click handling

    private func handleIconClick() {
        Log.overlay.info("Icon clicked (placeholder popover — replaced in Phase 1.2)")
        onIconClicked?()
        showPlaceholderPopover()
    }

    private var placeholderPopover: NSPopover?

    private func showPlaceholderPopover() {
        placeholderPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 240, height: 88)
        popover.contentViewController = NSHostingController(
            rootView: VStack(spacing: 6) {
                Text("Actions coming in Phase 1")
                    .font(.headline)
                Text("Focus is preserved — try typing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        )
        if let view = panel.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        placeholderPopover = popover
    }
}

extension OverlayController: FocusMonitorDelegate {
    func focusMonitor(_ monitor: FocusMonitor, fieldDidFocus field: FocusedField) {
        fieldDidFocus(field)
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldDidBlur previousBundleID: String?) {
        fieldDidBlur()
    }

    func focusMonitorTypingStarted(_ monitor: FocusMonitor) {
        typingStarted()
    }

    func focusMonitorTypingStopped(_ monitor: FocusMonitor) {
        typingStopped()
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated frame: CGRect) {
        fieldFrameUpdated(frame)
    }
}

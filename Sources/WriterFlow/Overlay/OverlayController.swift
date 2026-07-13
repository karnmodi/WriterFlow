import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: FloatingPanel
    private let actionPanel: FloatingPanel
    private let keyMonitor = PopoverKeyMonitor()

    private var currentField: FocusedField?
    private var isIconVisible: Bool = false
    private var isPopoverVisible: Bool = false
    private var highlightedIndex: Int = 0

    /// Phase 1.3 hooks ActionEngine here.
    var onActionSelected: ((WritingAction, FocusedField) -> Void)?

    private let iconSize = CGSize(width: 28, height: 28)
    private let popoverSize = CGSize(width: 220, height: 248)
    private let fieldPadding: CGFloat = 4

    init() {
        self.panel = FloatingPanel(size: iconSize)
        self.actionPanel = FloatingPanel(size: popoverSize)
        actionPanel.hasShadow = true
        panel.alphaValue = 0
        rewireIconHosting()
        rewirePopoverHosting()
    }

    private func rewireIconHosting() {
        let hosting = NSHostingView(rootView: FloatingIconView { [weak self] in
            self?.handleIconClick()
        })
        hosting.frame = NSRect(origin: .zero, size: iconSize)
        panel.contentView = hosting
    }

    private func rewirePopoverHosting() {
        let hosting = NSHostingView(rootView: popoverRootView)
        hosting.frame = NSRect(origin: .zero, size: popoverSize)
        actionPanel.contentView = hosting
        actionPanel.alphaValue = 0
    }

    private var popoverRootView: ActionPopoverView {
        ActionPopoverView(highlightedIndex: highlightedIndex) { [weak self] action in
            self?.handleActionSelected(action)
        }
    }

    // MARK: - Public API

    func toggleActionPopover() {
        if isPopoverVisible {
            dismissActionPopover()
        } else {
            showActionPopover()
        }
    }

    func showActionPopover() {
        guard let field = currentField else {
            Log.overlay.info("Action popover skipped — no focused editable field")
            return
        }
        guard !isPopoverVisible else { return }

        highlightedIndex = firstEnabledPopoverIndex()
        refreshPopoverContent()
        positionPopover(near: field.frame)
        isPopoverVisible = true

        actionPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            actionPanel.animator().alphaValue = 1.0
        }

        if !keyMonitor.install() {
            Log.overlay.error("Failed to install popover key monitor")
        }
        keyMonitor.onKey = { [weak self] event in
            self?.handleKeyEvent(event)
        }

        Log.overlay.info("Action popover opened")
    }

    func dismissActionPopover() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        keyMonitor.uninstall()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            actionPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.actionPanel.orderOut(nil)
            }
        })

        Log.overlay.info("Action popover dismissed")
    }

    // MARK: - FocusMonitor events

    func fieldDidFocus(_ field: FocusedField) {
        currentField = field
    }

    func fieldDidBlur() {
        currentField = nil
        dismissActionPopover()
        hideIcon()
    }

    func typingStarted() {
        guard let field = currentField else { return }
        positionIcon(near: field.frame)
        showIcon()
    }

    func typingStopped() {
        hideIcon()
    }

    func fieldFrameUpdated(_ frame: CGRect) {
        currentField = currentField.map {
            FocusedField(role: $0.role, frame: frame, appBundleID: $0.appBundleID, appPID: $0.appPID)
        }
        if isIconVisible { positionIcon(near: frame) }
        if isPopoverVisible { positionPopover(near: frame) }
    }

    // MARK: - Positioning

    private func positionIcon(near fieldFrame: CGRect) {
        let anchorX = fieldFrame.maxX - iconSize.width - fieldPadding
        let anchorY = fieldFrame.minY + fieldPadding
        let origin = clampToScreen(origin: CGPoint(x: anchorX, y: anchorY), size: iconSize)
        panel.setFrameOrigin(origin)
    }

    private func positionPopover(near fieldFrame: CGRect) {
        // Anchor above the field's bottom-right corner, near the icon position.
        let anchorX = fieldFrame.maxX - popoverSize.width - fieldPadding
        let anchorY = fieldFrame.minY + fieldPadding + iconSize.height + 6
        let origin = clampToScreen(origin: CGPoint(x: anchorX, y: anchorY), size: popoverSize)
        actionPanel.setFrameOrigin(origin)
    }

    private func clampToScreen(origin: CGPoint, size: CGSize) -> CGPoint {
        let rect = CGRect(origin: origin, size: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        var out = origin
        out.x = min(max(out.x, visible.minX + 2), visible.maxX - size.width - 2)
        out.y = min(max(out.y, visible.minY + 2), visible.maxY - size.height - 2)
        return out
    }

    // MARK: - Icon show/hide

    private func showIcon() {
        guard !isIconVisible else { return }
        isIconVisible = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }

    private func hideIcon() {
        guard isIconVisible else { return }
        isIconVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Interaction

    private func handleIconClick() {
        toggleActionPopover()
    }

    private func handleActionSelected(_ action: WritingAction) {
        guard action.isEnabled, let field = currentField else { return }
        Log.overlay.info("Action selected: \(action.title, privacy: .public)")
        dismissActionPopover()
        onActionSelected?(action, field)
    }

    private func handleKeyEvent(_ event: PopoverKeyMonitor.KeyEvent) {
        switch event {
        case .digit(let digit):
            if let action = WritingAction.matching(shortcut: digit) {
                handleActionSelected(action)
            }
        case .up:
            moveHighlight(by: -1)
        case .down:
            moveHighlight(by: 1)
        case .escape:
            dismissActionPopover()
        case .returnKey:
            let actions = WritingAction.popoverOrder
            guard highlightedIndex >= 0, highlightedIndex < actions.count else { return }
            handleActionSelected(actions[highlightedIndex])
        }
    }

    private func moveHighlight(by delta: Int) {
        let actions = WritingAction.popoverOrder
        guard !actions.isEmpty else { return }

        var next = highlightedIndex
        repeat {
            next = (next + delta + actions.count) % actions.count
        } while !actions[next].isEnabled && next != highlightedIndex

        guard actions[next].isEnabled else { return }
        highlightedIndex = next
        refreshPopoverContent()
    }

    private func firstEnabledPopoverIndex() -> Int {
        WritingAction.popoverOrder.firstIndex(where: \.isEnabled) ?? 0
    }

    private func refreshPopoverContent() {
        let hosting = NSHostingView(rootView: popoverRootView)
        hosting.frame = NSRect(origin: .zero, size: popoverSize)
        actionPanel.contentView = hosting
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

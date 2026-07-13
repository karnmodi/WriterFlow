import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: FloatingPanel
    private let actionPanel: FloatingPanel
    private let previewPanel: FloatingPanel
    private let keyMonitor = PopoverKeyMonitor()

    private var currentField: FocusedField?
    private var isIconVisible: Bool = false
    private var isPopoverVisible: Bool = false
    private var isPreviewVisible: Bool = false
    private var highlightedIndex: Int = 0

    private var previewText: String = ""
    private var previewStreaming: Bool = false
    private var previewCanReplace: Bool = false
    private var previewActionTitle: String = ""
    private var previewOriginalText: String = ""
    private var pendingSnapshot: FieldSnapshot?
    private var pendingAction: WritingAction?
    private var pendingEvent: ConversionEvent?
    private var pendingUndo: PendingUndo?
    private var isApplyingPreview = false

    private struct PendingUndo {
        let pid: pid_t
        let bundleID: String?
        let role: String
        let range: NSRange
        let originalText: String
    }

    var iconMode: IconMode = .onTyping
    var onActionSelected: ((WritingAction, FocusedField) -> Void)?

    private let iconSize = CGSize(width: 28, height: 28)
    private let popoverSize = CGSize(width: 220, height: 248)
    private let previewSize = CGSize(width: 300, height: 216)
    /// Fixed dock offset from the bottom of the visible screen (Whisperflow-style).
    private let iconBottomMargin: CGFloat = 36

    init() {
        self.panel = FloatingPanel(size: iconSize, level: .popUpMenu)
        self.actionPanel = FloatingPanel(size: popoverSize)
        self.previewPanel = FloatingPanel(size: previewSize)
        actionPanel.hasShadow = true
        previewPanel.hasShadow = true
        panel.alphaValue = 0
        rewireIconHosting()
        rewirePopoverHosting()
        rewirePreviewHosting()
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

    private func rewirePreviewHosting() {
        let hosting = NSHostingView(rootView: previewRootView)
        hosting.frame = NSRect(origin: .zero, size: previewSize)
        previewPanel.contentView = hosting
        previewPanel.alphaValue = 0
    }

    private var popoverRootView: ActionPopoverView {
        ActionPopoverView(highlightedIndex: highlightedIndex) { [weak self] action in
            self?.handleActionSelected(action)
        }
    }

    private var previewRootView: PreviewCardView {
        PreviewCardView(
            actionTitle: previewActionTitle,
            text: previewText,
            originalText: previewOriginalText,
            action: pendingAction,
            isStreaming: previewStreaming,
            canReplace: previewCanReplace,
            onReplace: { [weak self] in self?.applyPreview() },
            onCopy: { [weak self] in self?.copyPreview() },
            onRetry: { [weak self] in self?.retryPreview() },
            onDiscard: { [weak self] in self?.discardPreview() }
        )
    }

    // MARK: - Public API

    func toggleActionPopover() {
        if isPopoverVisible { dismissActionPopover() } else { showActionPopover() }
    }

    func showActionPopover() {
        guard let field = currentField else {
            Log.overlay.info("Action popover skipped — no focused editable field")
            return
        }
        guard !isPopoverVisible else { return }

        highlightedIndex = firstEnabledPopoverIndex()
        refreshPopoverContent()
        positionPanelAboveIcon(actionPanel, size: popoverSize, field: field)
        isPopoverVisible = true

        actionPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            actionPanel.animator().alphaValue = 1.0
        }

        if !keyMonitor.install() {
            Log.overlay.error("Failed to install popover key monitor")
        }
        keyMonitor.onKey = { [weak self] event in self?.handleKeyEvent(event) }
        Log.overlay.info("Action popover opened")
    }

    func dismissActionPopover() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        if !isPreviewVisible {
            keyMonitor.uninstall()
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            actionPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.actionPanel.orderOut(nil) }
        })
    }

    func beginPreview(action: WritingAction) {
        previewActionTitle = action.title
        previewText = ""
        previewOriginalText = ""
        previewStreaming = true
        previewCanReplace = false
        pendingAction = action
        pendingSnapshot = nil
        pendingEvent = nil
        pendingUndo = nil

        guard let field = currentField else { return }
        dismissActionPopover()
        positionPanelAboveIcon(previewPanel, size: previewSize, field: field)
        refreshPreviewContent()
        isPreviewVisible = true
        previewPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            previewPanel.animator().alphaValue = 1.0
        }
        installPreviewKeyMonitor()
    }

    func appendPreview(_ delta: String) {
        previewText += delta
        refreshPreviewContent()
    }

    func finishPreview(output: String, snapshot: FieldSnapshot, event: ConversionEvent) {
        previewText = output
        previewOriginalText = snapshot.actionText
        previewStreaming = false
        previewCanReplace = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pendingSnapshot = snapshot
        pendingEvent = event
        refreshPreviewContent()
        installPreviewKeyMonitor()
    }

    func failPreview(message: String) {
        previewStreaming = false
        previewCanReplace = false
        dismissPreview()
        ErrorToast.show(message)
    }

    // MARK: - Event logging

    /// Persists the pending conversion event exactly once, tagged with the
    /// terminal outcome (Replace/Copy → accepted, Discard/Retry/blur → not).
    private func finalizeEvent(accepted: Bool) {
        guard var event = pendingEvent else { return }
        pendingEvent = nil
        event.accepted = accepted
        Task { await ConversionEventStore.shared.append(event) }
    }

    // MARK: - FocusMonitor events

    func fieldDidFocus(_ field: FocusedField) {
        currentField = field
        guard iconMode == .alwaysOnFocus, hasValidFieldFrame(field) else { return }
        positionIcon(in: field)
        showIcon()
    }

    func fieldDidBlur() {
        currentField = nil
        dismissActionPopover()
        finalizeEvent(accepted: false)
        dismissPreview()
        hideIcon()
    }

    func typingStarted() {
        guard iconMode != .hotkeyOnly,
              let field = currentField,
              hasValidFieldFrame(field) else { return }
        positionIcon(in: field)
        showIcon()
    }

    func typingStopped() {
        guard iconMode == .onTyping else { return }
        hideIcon()
    }

    func fieldFrameUpdated(_ field: FocusedField) {
        currentField = field
        if isIconVisible {
            positionIcon(in: field)
        } else if iconMode == .alwaysOnFocus, hasValidFieldFrame(field) {
            positionIcon(in: field)
            showIcon()
        }
        if isPopoverVisible {
            positionPanelAboveIcon(actionPanel, size: popoverSize, field: field)
        }
        if isPreviewVisible {
            positionPanelAboveIcon(previewPanel, size: previewSize, field: field)
        }
    }

    // MARK: - Positioning

    private func hasValidFieldFrame(_ field: FocusedField) -> Bool {
        CaretEstimator.isUsableFieldFrame(field.frame)
    }

    /// Screen containing the focused field (for multi-monitor bottom-center dock).
    private func screenForField(_ field: FocusedField) -> NSScreen? {
        let frame = field.frame
        return NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Fixed bottom-center of the active screen — same spot for every input.
    private func bottomCenterOrigin(for size: CGSize, on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        return CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + iconBottomMargin
        )
    }

    private func positionIcon(in field: FocusedField) {
        guard hasValidFieldFrame(field), let screen = screenForField(field) else { return }
        panel.setFrameOrigin(bottomCenterOrigin(for: iconSize, on: screen))
        Log.overlay.debug("Icon placement screenBottomCenter")
    }

    private func positionPanelAboveIcon(
        _ target: NSWindow,
        size: CGSize,
        field: FocusedField
    ) {
        guard hasValidFieldFrame(field), let screen = screenForField(field) else { return }
        let iconOrigin = bottomCenterOrigin(for: iconSize, on: screen)
        let origin = CGPoint(
            x: iconOrigin.x + iconSize.width / 2 - size.width / 2,
            y: iconOrigin.y + iconSize.height + 10
        )
        target.setFrameOrigin(clampToScreen(origin: origin, size: size, on: screen))
    }

    private func clampToScreen(origin: CGPoint, size: CGSize, on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        var out = origin
        out.x = min(max(out.x, visible.minX + 4), visible.maxX - size.width - 4)
        out.y = min(max(out.y, visible.minY + 4), visible.maxY - size.height - 4)
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
            Task { @MainActor in self?.panel.orderOut(nil) }
        })
    }

    private func dismissPreview() {
        guard isPreviewVisible else { return }
        isPreviewVisible = false
        previewText = ""
        previewOriginalText = ""
        previewStreaming = false
        previewCanReplace = false
        pendingSnapshot = nil
        pendingAction = nil
        keyMonitor.uninstall()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            previewPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.previewPanel.orderOut(nil) }
        })
    }

    /// User-initiated close without accepting the result (Discard button / Esc).
    private func discardPreview() {
        finalizeEvent(accepted: false)
        dismissPreview()
    }

    // MARK: - Interaction

    private func handleIconClick() {
        Log.overlay.info("Icon clicked")
        toggleActionPopover()
    }

    private func handleActionSelected(_ action: WritingAction) {
        guard action.isEnabled, let field = currentField else { return }
        Log.overlay.info("Action selected: \(action.title, privacy: .public)")
        beginPreview(action: action)
        onActionSelected?(action, field)
    }

    private func applyPreview() {
        guard let snapshot = pendingSnapshot, let field = currentField else {
            ErrorToast.show("Couldn't apply — field changed. Try again.")
            discardPreview()
            return
        }
        guard previewCanReplace, !previewText.isEmpty, !isApplyingPreview else { return }
        isApplyingPreview = true

        let text = previewText
        let pid = field.appPID
        let bundleID = field.appBundleID
        let range = snapshot.actionRange
        let role = snapshot.role
        let originalText = snapshot.actionText
        let postReplaceRange = NSRange(location: range.location, length: (text as NSString).length)

        hidePanelsForReplace()
        keyMonitor.uninstall()

        Task {
            let result = await TextWriter.replace(
                pid: pid,
                range: range,
                with: text,
                bundleID: bundleID,
                role: role
            )
            await MainActor.run {
                isApplyingPreview = false
                finalizeEvent(accepted: true)
                dismissPreview()
                switch result {
                case .selectedTextReplaced, .fullValueReplaced, .clipboardPasted:
                    pendingUndo = PendingUndo(
                        pid: pid,
                        bundleID: bundleID,
                        role: role,
                        range: postReplaceRange,
                        originalText: originalText
                    )
                    UndoToast.show(message: "Replaced ✓") { [weak self] in
                        self?.restoreOriginal()
                    }
                case .failed(let reason):
                    ErrorToast.show("Replace failed: \(reason)")
                }
            }
        }
    }

    /// Copies the preview result to the clipboard and closes the card — an
    /// alternative to Replace when the user wants to paste it elsewhere.
    private func copyPreview() {
        guard previewCanReplace, !previewText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewText, forType: .string)
        finalizeEvent(accepted: true)
        dismissPreview()
        ErrorToast.show("Copied ✓")
    }

    /// Discards the current attempt and re-runs the same action against the
    /// field's live contents.
    private func retryPreview() {
        guard let action = pendingAction, let field = currentField else { return }
        finalizeEvent(accepted: false)
        beginPreview(action: action)
        onActionSelected?(action, field)
    }

    private func restoreOriginal() {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil
        Task {
            _ = await TextWriter.replace(
                pid: undo.pid,
                range: undo.range,
                with: undo.originalText,
                bundleID: undo.bundleID,
                role: undo.role
            )
        }
    }

    private func hidePanelsForReplace() {
        previewPanel.orderOut(nil)
        previewPanel.alphaValue = 0
        actionPanel.orderOut(nil)
        actionPanel.alphaValue = 0
    }

    private func installPreviewKeyMonitor() {
        if !keyMonitor.install() {
            Log.overlay.error("Failed to install preview key monitor")
        }
        keyMonitor.onKey = { [weak self] event in self?.handlePreviewKeyEvent(event) }
    }

    private func handlePreviewKeyEvent(_ event: PopoverKeyMonitor.KeyEvent) {
        switch event {
        case .escape:
            discardPreview()
        case .returnKey:
            if previewCanReplace, !previewText.isEmpty {
                applyPreview()
            }
        case .copy:
            copyPreview()
        case .retry:
            retryPreview()
        default:
            break
        }
    }

    private func handleKeyEvent(_ event: PopoverKeyMonitor.KeyEvent) {
        switch event {
        case .digit(let digit):
            if let action = WritingAction.matching(shortcut: digit) {
                handleActionSelected(action)
            }
        case .up: moveHighlight(by: -1)
        case .down: moveHighlight(by: 1)
        case .escape: dismissActionPopover()
        case .returnKey:
            let actions = WritingAction.popoverOrder
            guard highlightedIndex >= 0, highlightedIndex < actions.count else { return }
            handleActionSelected(actions[highlightedIndex])
        case .copy, .retry:
            break
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

    private func refreshPreviewContent() {
        let hosting = NSHostingView(rootView: previewRootView)
        hosting.frame = NSRect(origin: .zero, size: previewSize)
        previewPanel.contentView = hosting
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

    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated field: FocusedField) {
        fieldFrameUpdated(field)
    }
}

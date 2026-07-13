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
    private var previewPromptBuilderPhase: PromptBuilderPreviewPhase?
    private var previewClarifyQuestions: [PromptBuilderOutputParser.ClarifyQuestion] = []
    private var previewClarifySelections: [String: String] = [:]
    private var previewStreaming: Bool = false
    private var previewCanReplace: Bool = false
    private var previewActionTitle: String = ""
    private var previewOriginalText: String = ""
    private var pendingSnapshot: FieldSnapshot?
    private var pendingAction: WritingAction?
    private var pendingEvent: ConversionEvent?
    private var pendingUndo: PendingUndo?
    private var isApplyingPreview = false

    private var recommendedAction: WritingAction?
    private var userMovedHighlight = false
    private var isCustomInputActive = false
    private var showCustomField = false
    private var customText = ""
    private var showPromptBuilderField = false
    private var promptBuilderText = ""
    private var pendingPopoverRefresh = false

    private struct PendingUndo {
        let pid: pid_t
        let bundleID: String?
        let role: String
        let range: NSRange
        let originalText: String
    }

    var iconMode: IconMode = .onTyping
    var onActionSelected: ((WritingAction, FocusedField) -> Void)?
    var onCustomActionSelected: ((String, FocusedField) -> Void)?
    var onPromptBuilderActionSelected: ((String, FocusedField) -> Void)?
    var onPromptBuilderAnswersSelected: (([(question: String, answer: String)], FocusedField) -> Void)?
    var onRequestRecommendation: ((FocusedField) -> Void)?
    var onCancelRecommendation: (() -> Void)?

    private let iconSize = CGSize(width: 28, height: 28)
    private let popoverSize = CGSize(width: 230, height: 360)
    private let previewSize = CGSize(width: 300, height: 220)
    private let promptBuilderPreviewSize = CGSize(width: 300, height: 320)
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
        actionPanel.contentView = makePopoverHostingView()
        actionPanel.alphaValue = 0
    }

    private func makePopoverHostingView() -> NSHostingView<ActionPopoverView> {
        let hosting = NSHostingView(rootView: popoverRootView)
        hosting.frame = NSRect(origin: .zero, size: popoverSize)
        return hosting
    }

    private func rewirePreviewHosting() {
        let hosting = NSHostingView(rootView: previewRootView)
        hosting.frame = NSRect(origin: .zero, size: effectivePreviewSize)
        previewPanel.contentView = hosting
        previewPanel.alphaValue = 0
    }

    private var effectivePreviewSize: CGSize {
        pendingAction == .promptBuilder ? promptBuilderPreviewSize : previewSize
    }

    private var popoverRootView: ActionPopoverView {
        ActionPopoverView(
            highlightedIndex: highlightedIndex,
            isCustomHighlighted: isCustomHighlighted,
            recommendedAction: recommendedAction,
            recentCustomInstructions: SettingsStore.shared.recentCustomInstructions,
            showPromptBuilderField: Binding(
                get: { self.showPromptBuilderField },
                set: { self.showPromptBuilderField = $0 }
            ),
            promptBuilderText: Binding(
                get: { self.promptBuilderText },
                set: { self.promptBuilderText = $0 }
            ),
            showCustomField: Binding(
                get: { self.showCustomField },
                set: { self.showCustomField = $0 }
            ),
            customText: Binding(
                get: { self.customText },
                set: { self.customText = $0 }
            ),
            onSelect: { [weak self] action in self?.handleActionSelected(action) },
            onPromptBuilderSubmit: { [weak self] brief in self?.handlePromptBuilderSubmit(brief) },
            onCustomSubmit: { [weak self] instruction in self?.handleCustomSubmit(instruction) },
            onCustomFocusRequested: { [weak self] in self?.beginCustomInput() },
            onCustomOpen: { [weak self] in self?.openCustomInput() },
            onPromptBuilderFieldAppeared: { [weak self] in self?.focusCustomField() },
            onCustomFieldAppeared: { [weak self] in self?.focusCustomField() },
            onCustomCancelled: { [weak self] in self?.endCustomInput() },
            onPromptBuilderCancelled: { [weak self] in self?.endCustomInput() }
        )
    }

    /// Virtual row index after the six list actions — keyboard-navigable Custom entry.
    private var customRowIndex: Int { WritingAction.popoverOrder.count }

    private var isCustomHighlighted: Bool {
        highlightedIndex == customRowIndex && !showCustomField
    }

    private var previewRootView: PreviewCardView {
        PreviewCardView(
            actionTitle: previewActionTitle,
            text: previewText,
            promptBuilderPhase: previewPromptBuilderPhase,
            clarifyQuestions: previewClarifyQuestions,
            clarifySelections: previewClarifySelections,
            originalText: previewOriginalText,
            action: pendingAction,
            isStreaming: previewStreaming,
            canReplace: previewCanReplace,
            onSelectClarifyAnswer: { [weak self] questionID, answer in
                self?.selectClarifyAnswer(questionID: questionID, answer: answer)
            },
            onContinueClarify: { [weak self] in self?.continuePromptBuilderClarify() },
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
        recommendedAction = nil
        userMovedHighlight = false
        showCustomField = false
        customText = ""
        showPromptBuilderField = false
        promptBuilderText = ""
        pendingPopoverRefresh = false
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
        onRequestRecommendation?(field)
        Log.overlay.info("Action popover opened")
    }

    /// Applies an async recommendation, ignoring it if the popover has since
    /// closed or moved to a different field.
    func applyRecommendation(_ action: WritingAction, for field: FocusedField) {
        guard isPopoverVisible else {
            Log.overlay.debug("Recommendation dropped — popover closed")
            return
        }
        guard let current = currentField, current.matchesRecommendationTarget(field) else {
            Log.overlay.debug("Recommendation dropped — field identity changed")
            return
        }
        recommendedAction = action
        Log.overlay.info("Recommendation applied: \(action.title, privacy: .public)")
        // Don't steal highlight while the user is typing an inline instruction
        // or has already moved with arrows/hover intent.
        if !userMovedHighlight, !isCustomInputActive,
           let index = WritingAction.popoverOrder.firstIndex(of: action) {
            highlightedIndex = index
        }
        refreshPopoverContent()
    }

    func dismissActionPopover() {
        guard isPopoverVisible else { return }
        isPopoverVisible = false
        showCustomField = false
        customText = ""
        showPromptBuilderField = false
        promptBuilderText = ""
        pendingPopoverRefresh = false
        endCustomInput()
        onCancelRecommendation?()
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
        previewPromptBuilderPhase = action == .promptBuilder ? .analyzing : nil
        previewClarifyQuestions = []
        previewClarifySelections = [:]
        previewOriginalText = ""
        previewStreaming = true
        previewCanReplace = false
        pendingAction = action
        pendingSnapshot = nil
        pendingEvent = nil
        pendingUndo = nil

        guard let field = currentField else { return }
        dismissActionPopover()
        positionPanelAboveIcon(previewPanel, size: effectivePreviewSize, field: field)
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

    func updatePromptBuilderPreview(prompt: String) {
        previewText = prompt
        previewPromptBuilderPhase = .prompt
        refreshPreviewContent()
    }

    func showPromptBuilderClarify(questions: [PromptBuilderOutputParser.ClarifyQuestion]) {
        previewClarifyQuestions = questions
        previewClarifySelections = [:]
        previewPromptBuilderPhase = .clarify
        previewText = ""
        previewStreaming = false
        previewCanReplace = false
        refreshPreviewContent()
        installPreviewKeyMonitor()
    }

    func finishPreview(output: String, snapshot: FieldSnapshot, event: ConversionEvent) {
        previewText = output
        previewPromptBuilderPhase = pendingAction == .promptBuilder ? .prompt : nil
        previewClarifyQuestions = []
        previewClarifySelections = [:]
        previewOriginalText = snapshot.actionText
        previewStreaming = false
        previewCanReplace = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && snapshot.supportsReplace
        pendingSnapshot = snapshot
        pendingEvent = event
        refreshPreviewContent()
        installPreviewKeyMonitor()
    }

    private func selectClarifyAnswer(questionID: String, answer: String) {
        previewClarifySelections[questionID] = answer
        refreshPreviewContent()
    }

    private func continuePromptBuilderClarify() {
        guard let field = currentField,
              !previewClarifyQuestions.isEmpty else { return }

        let answers = previewClarifyQuestions.compactMap { question -> (question: String, answer: String)? in
            guard let answer = previewClarifySelections[question.id] else { return nil }
            return (question: question.text, answer: answer)
        }
        guard answers.count == previewClarifyQuestions.count else { return }

        previewStreaming = true
        previewPromptBuilderPhase = .prompt
        previewText = ""
        previewClarifyQuestions = []
        previewClarifySelections = [:]
        previewCanReplace = false
        refreshPreviewContent()

        onPromptBuilderAnswersSelected?(answers, field)
    }

    func failPreview(message: String) {
        previewStreaming = false
        previewCanReplace = false
        dismissPreview()
        ErrorToast.show(message, belowIcon: dockIconAnchor())
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
        // Custom instruction entry deliberately activates WriterFlow and takes
        // key focus (golden-rule exception). That blurs the host field — do NOT
        // tear down the popover or clear currentField while typing the prompt.
        if isCustomInputActive {
            return
        }
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
            positionPanelAboveIcon(previewPanel, size: effectivePreviewSize, field: field)
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

    /// Anchor rect for toasts — live dock icon frame, or computed bottom-center slot.
    private func dockIconAnchor() -> CGRect {
        if isIconVisible, panel.isVisible {
            return panel.frame
        }
        guard let field = currentField,
              hasValidFieldFrame(field),
              let screen = screenForField(field) else {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return .zero }
            return MessageToast.defaultIconFrame(
                iconSize: iconSize,
                iconBottomMargin: iconBottomMargin,
                on: screen
            )
        }
        let origin = bottomCenterOrigin(for: iconSize, on: screen)
        return CGRect(origin: origin, size: iconSize)
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
        previewPromptBuilderPhase = nil
        previewClarifyQuestions = []
        previewClarifySelections = [:]
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

        if action == .promptBuilder {
            Task {
                await handlePromptBuilderSelected(field: field)
            }
            return
        }

        beginPreview(action: action)
        onActionSelected?(action, field)
    }

    private func handlePromptBuilderSelected(field: FocusedField) async {
        let snapshot = await ContextExtractor.readFocusedField(
            pid: field.appPID,
            bundleID: field.appBundleID
        )
        let fieldText = snapshot?.actionText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if fieldText.isEmpty {
            openPromptBuilderInput()
            return
        }

        beginPreview(action: .promptBuilder)
        onActionSelected?(.promptBuilder, field)
    }

    private func handlePromptBuilderSubmit(_ brief: String) {
        endCustomInput()
        let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let field = currentField else { return }
        Log.overlay.info("Prompt Builder submitted from brief box")
        beginPreview(action: .promptBuilder)
        onPromptBuilderActionSelected?(trimmed, field)
    }

    private func handleCustomSubmit(_ instruction: String) {
        endCustomInput()
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let field = currentField else { return }
        SettingsStore.shared.recordCustomInstruction(trimmed)
        Log.overlay.info("Custom action submitted")
        beginPreview(action: .custom)
        onCustomActionSelected?(trimmed, field)
    }

    /// Scoped, deliberate exception to "never steal focus" (golden rule #1) —
    /// only while the user is actively typing a Custom instruction. The global
    /// popover key monitor is uninstalled so the native text field gets normal
    /// keyboard handling (arrows, backspace, IME); reinstalled in `endCustomInput`.
    private func beginCustomInput() {
        guard !isCustomInputActive else { return }
        isCustomInputActive = true
        keyMonitor.uninstall()
        actionPanel.allowsKeyWhenNeeded = true
        NSApp.activate(ignoringOtherApps: true)
    }

    private func focusCustomField() {
        actionPanel.makeKey()
    }

    private func openCustomInput() {
        // Mark active BEFORE activating WriterFlow so the ensuing host-field
        // blur is ignored by fieldDidBlur and does not dismiss the popover.
        showPromptBuilderField = false
        promptBuilderText = ""
        beginCustomInput()
        showCustomField = true
        highlightedIndex = customRowIndex
        userMovedHighlight = true
        actionPanel.contentView = makePopoverHostingView()
        focusCustomField()
    }

    private func openPromptBuilderInput() {
        showCustomField = false
        customText = ""
        beginCustomInput()
        showPromptBuilderField = true
        if let index = WritingAction.popoverOrder.firstIndex(of: .promptBuilder) {
            highlightedIndex = index
        }
        userMovedHighlight = true
        actionPanel.contentView = makePopoverHostingView()
        focusCustomField()
    }

    private func endCustomInput() {
        guard isCustomInputActive else { return }
        isCustomInputActive = false
        actionPanel.allowsKeyWhenNeeded = false
        if let field = currentField {
            NSRunningApplication(processIdentifier: field.appPID)?.activate()
        }
        if isPopoverVisible {
            if !keyMonitor.install() {
                Log.overlay.error("Failed to reinstall popover key monitor")
            }
            keyMonitor.onKey = { [weak self] event in self?.handleKeyEvent(event) }
            // Always remake after Custom closes so the list/Suggested state returns.
            pendingPopoverRefresh = false
            refreshPopoverContent()
        } else if pendingPopoverRefresh {
            pendingPopoverRefresh = false
        }
    }

    private func applyPreview() {
        guard let snapshot = pendingSnapshot, let field = currentField else {
            ErrorToast.show("Couldn't apply — field changed. Try again.", belowIcon: dockIconAnchor())
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
                    UndoToast.show(message: "Replaced ✓", belowIcon: dockIconAnchor()) { [weak self] in
                        self?.restoreOriginal()
                    }
                case .failed(let reason):
                    ErrorToast.show("Replace failed: \(reason)", belowIcon: dockIconAnchor())
                }
            }
        }
    }

    /// Copies the preview result to the clipboard and closes the card — an
    /// alternative to Replace when the user wants to paste it elsewhere.
    private func copyPreview() {
        guard !previewText.isEmpty, (previewCanReplace || pendingSnapshot?.supportsReplace == false) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewText, forType: .string)
        finalizeEvent(accepted: true)
        dismissPreview()
        ErrorToast.show("Copied to clipboard", duration: 2.0, belowIcon: dockIconAnchor(), style: .success)
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
            if previewPromptBuilderPhase == .clarify {
                if previewClarifyQuestions.allSatisfy({ previewClarifySelections[$0.id] != nil }) {
                    continuePromptBuilderClarify()
                }
            } else if previewCanReplace, !previewText.isEmpty {
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
            if digit == 7 {
                openCustomInput()
            } else if let action = WritingAction.matching(shortcut: digit) {
                handleActionSelected(action)
            }
        case .up: moveHighlight(by: -1)
        case .down: moveHighlight(by: 1)
        case .escape: dismissActionPopover()
        case .returnKey:
            if isCustomHighlighted {
                openCustomInput()
                return
            }
            let actions = WritingAction.popoverOrder
            guard highlightedIndex >= 0, highlightedIndex < actions.count else { return }
            handleActionSelected(actions[highlightedIndex])
        case .copy, .retry:
            break
        }
    }

    private func moveHighlight(by delta: Int) {
        userMovedHighlight = true
        let rowCount = customRowIndex + 1
        guard rowCount > 0 else { return }
        var next = highlightedIndex
        repeat {
            next = (next + delta + rowCount) % rowCount
        } while next < customRowIndex
            && !WritingAction.popoverOrder[next].isEnabled
            && next != highlightedIndex
        if next < customRowIndex, !WritingAction.popoverOrder[next].isEnabled { return }
        highlightedIndex = next
        refreshPopoverContent()
    }

    private func firstEnabledPopoverIndex() -> Int {
        WritingAction.popoverOrder.firstIndex(where: \.isEnabled) ?? 0
    }

    private func refreshPopoverContent() {
        if isCustomInputActive {
            pendingPopoverRefresh = true
            return
        }
        actionPanel.contentView = makePopoverHostingView()
    }

    private func refreshPreviewContent() {
        let hosting = NSHostingView(rootView: previewRootView)
        hosting.frame = NSRect(origin: .zero, size: effectivePreviewSize)
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

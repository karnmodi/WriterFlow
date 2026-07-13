import AppKit
import ApplicationServices
import Foundation

/// Central focus + typing coordinator.
///
/// - Attaches an AXObserver to the frontmost app (re-attached on app switches).
/// - Listens to a passive CGEventTap for a "user is typing" timestamp.
/// - Classifies the focused element into an editable / secure / non-editable bucket.
/// - Emits high-level events to a delegate.
@MainActor
final class FocusMonitor {
    weak var delegate: FocusMonitorDelegate?

    private let axQueue = DispatchQueue(label: "com.karan.writerflow.ax", qos: .userInitiated)
    private let eventTap = EventTap()

    private var currentAppObserver: AppObserver?
    private var currentField: FocusedField?
    private var typingActive: Bool = false
    private var stopTypingTask: Task<Void, Never>?
    private var frameTimer: Timer?
    private var quirksApplied: Set<pid_t> = []
    private var isRunning: Bool = false

    // 4-second debounce per phase-0 spec.
    private let typingStopDelay: TimeInterval = 4.0

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Event tap for typing signal
        if !eventTap.install() {
            Log.focus.error("Failed to install keystroke event tap — Input Monitoring likely not granted")
        }
        eventTap.onKeyDown = { [weak self] in
            // Main run loop already.
            self?.handleKeystroke()
        }

        // Screen height snapshot for AX->Cocoa conversion; refresh on changes.
        MainScreenSnapshot.primaryHeight = NSScreen.main?.frame.height ?? 1080
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Watch for app switches (re-attach observer)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attach(to: frontmost)
        }
        Log.focus.info("FocusMonitor started")
    }

    /// Stop and start — used when permissions are granted mid-session.
    func restart() {
        stop()
        start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        eventTap.uninstall()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)

        currentAppObserver?.stop()
        currentAppObserver = nil

        stopTypingTask?.cancel()
        stopTypingTask = nil
        frameTimer?.invalidate()
        frameTimer = nil

        if let previous = currentField {
            delegate?.focusMonitor(self, fieldDidBlur: previous.appBundleID)
            currentField = nil
        }
        Log.focus.info("FocusMonitor stopped")
    }

    // MARK: - App attachment

    @objc private func didActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        attach(to: app)
    }

    private func attach(to app: NSRunningApplication) {
        // Skip WriterFlow itself.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }

        // Detach previous.
        currentAppObserver?.stop()
        clearCurrentField()

        let observer = AppObserver(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
        observer.onFocusChanged = { [weak self, weak observer] element in
            guard let self, let observer else { return }
            self.handleFocusChanged(element: element, in: observer)
        }
        observer.onValueChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.handleValueChanged() }
        }
        observer.start()
        currentAppObserver = observer

        applyAccessibilityQuirks(for: app, on: observer)
        Log.focus.info("Attached to \(app.bundleIdentifier ?? "?", privacy: .public) pid=\(app.processIdentifier)")
    }

    /// Enable enhanced AX trees for browsers (Gmail in Chrome/Safari) and Electron
    /// editors (Cursor, VS Code, Slack, Notion). Safe to attempt on every app —
    /// unsupported attributes are ignored by the target process.
    private func applyAccessibilityQuirks(for app: NSRunningApplication, on observer: AppObserver) {
        guard !quirksApplied.contains(app.processIdentifier) else { return }
        observer.setAppAttribute(AXAttr.enhancedUserInterface, boolValue: true)
        observer.setAppAttribute(AXAttr.manualAccessibility, boolValue: true)
        quirksApplied.insert(app.processIdentifier)
        Log.focus.info(
            "Applied accessibility quirks for \(app.bundleIdentifier ?? "?", privacy: .public)"
        )
    }

    // MARK: - Focus + classification

    private func handleFocusChanged(element: AXUIElement?, in observer: AppObserver) {
        guard let element else {
            observer.observeValueChanges(on: nil)
            clearCurrentField()
            return
        }
        observer.observeValueChanges(on: element)
        let pid = observer.pid
        let bundleID = observer.bundleID
        axQueue.async { [weak self] in
            let classified = FocusedFieldClassifier.classify(element, pid: pid, bundleID: bundleID)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let field = classified {
                    self.applyClassifiedField(field)
                } else {
                    self.clearCurrentField()
                }
            }
        }
    }

    private func handleValueChanged() {
        guard currentAppObserver != nil else { return }
        pollFrame()
        if currentField == nil {
            bootstrapFocusFromKeystrokeSync()
        }
    }

    private func applyClassifiedField(_ field: FocusedField) {
        if currentField != field {
            currentField = field
            delegate?.focusMonitor(self, fieldDidFocus: field)
            restartFrameTimer()
        }
    }

    private func clearCurrentField() {
        stopTypingTask?.cancel()
        stopTypingTask = nil
        frameTimer?.invalidate()
        frameTimer = nil
        if typingActive {
            typingActive = false
            delegate?.focusMonitorTypingStopped(self)
        }
        if let previous = currentField {
            delegate?.focusMonitor(self, fieldDidBlur: previous.appBundleID)
            currentField = nil
        }
    }

    // MARK: - Typing signal

    private func handleKeystroke() {
        if currentField == nil {
            bootstrapFocusFromKeystrokeSync()
        }
        guard currentField != nil else { return }
        pollFrame()
        if !typingActive {
            typingActive = true
            delegate?.focusMonitorTypingStarted(self)
        }
        scheduleTypingStopped()
    }

    private func bootstrapFocusFromKeystrokeSync() {
        guard let observer = currentAppObserver else { return }
        let pid = observer.pid
        let bundleID = observer.bundleID
        let classified: FocusedField? = axQueue.sync {
            let appElement = AXUIElementCreateApplication(pid)
            guard let raw = FocusedElementResolver.focusedElement(in: appElement) else { return nil }
            return FocusedFieldClassifier.classify(raw, pid: pid, bundleID: bundleID)
        }
        if let classified {
            applyClassifiedField(classified)
            if let focused = FocusedElementResolver.focusedElement(
                in: AXUIElementCreateApplication(pid)
            ) {
                observer.observeValueChanges(on: focused)
            }
        }
    }

    private func scheduleTypingStopped() {
        stopTypingTask?.cancel()
        let delay = typingStopDelay
        stopTypingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.typingActive {
                self.typingActive = false
                self.delegate?.focusMonitorTypingStopped(self)
            }
        }
    }

    // MARK: - Frame polling (only while a field is focused)

    private func restartFrameTimer() {
        frameTimer?.invalidate()
        guard currentField != nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func pollFrame() {
        guard let observer = currentAppObserver, let field = currentField else { return }
        let pid = observer.pid
        let bundleID = observer.bundleID
        axQueue.async { [weak self] in
            _ = self  // keep alive across queue hop
            let appElement = AXUIElementCreateApplication(pid)
            guard let rawFocused = FocusedElementResolver.focusedElement(in: appElement),
                  let focused = FocusedElementResolver.resolveEditable(from: rawFocused),
                  let axRect = AXCall.axFrame(focused)
            else { return }
            let cocoaRect = AXCoords.toCocoa(axRect)
            let (anchor, _) = CaretEstimator.placement(for: focused, cocoaFieldFrame: cocoaRect)
            let expectedBundle = field.appBundleID
            let role = field.role
            let previous = field
            Task { @MainActor [weak self] in
                guard let self, self.currentField?.appBundleID == expectedBundle else { return }
                if cocoaRect != previous.frame || anchor != previous.anchorRect {
                    let updated = FocusedField(
                        role: role,
                        frame: cocoaRect,
                        anchorRect: anchor,
                        appBundleID: bundleID,
                        appPID: pid
                    )
                    self.currentField = updated
                    self.delegate?.focusMonitor(self, fieldFrameUpdated: updated)
                }
            }
        }
    }

    // MARK: - Screen changes

    @objc private func screenParametersChanged() {
        MainScreenSnapshot.primaryHeight = NSScreen.main?.frame.height ?? 1080
    }
}

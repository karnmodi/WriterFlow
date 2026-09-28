import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppWindowVisibilityDelegate, FocusMonitorDelegate {
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private let permissions = PermissionsCoordinator()
    private lazy var onboarding = OnboardingWindowController(permissions: permissions)
    private lazy var dashboardWindow = DashboardWindowController(modelsConfig: modelsConfig, deviceSession: deviceSession)
    private let focusMonitor = FocusMonitor()
    private let overlay = OverlayController()
    private let globalHotkey = GlobalHotkey()
    private let naturalLanguageHotkey = GlobalHotkey(id: 2)
    private let contextCapsules = ContextCapsuleStore()
    private let dependencies = AppDependencies.shared
    private lazy var settings = SettingsStore.shared
    private lazy var modelsConfig = dependencies.modelsConfig
    // Stage 5.2: device-session state lives in one place, queried via the
    // protocol — not scattered ad hoc Keychain reads through AppDelegate
    // the way the v1 BYO-key readiness check at `needsAzureSetup` below is.
    private lazy var deviceSession = dependencies.deviceSession
    private lazy var writerFlowAPI = dependencies.writerFlowAPI
    private lazy var inferenceTransport = dependencies.inferenceTransport
    private lazy var actionEngine = ActionEngine(
        legacyClient: dependencies.legacyActionClient,
        inferenceTransport: inferenceTransport,
        deviceSession: deviceSession
    )
    private lazy var autoActionCoordinator = AutoActionCoordinator(
        capsules: contextCapsules,
        engine: actionEngine,
        overlay: overlay
    )
    private lazy var recommendationEngine = RecommendationEngine(
        classifier: dependencies.recommendationClassifier
    )
    private var cancellables: Set<AnyCancellable> = []
    private var hadAccessibility = false
    private var hadInputMonitoring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Stage 4.4: bail out early if we relocated to /Applications and are relaunching
        // from there — nothing below should stand up against the DMG-mounted copy.
        AppRelocator.relocateIfNeededFromDMG()

        // Open/migrate/unlock the encrypted store before constructing Dashboard
        // view models or any singleton that can read account content.
        _ = WriterFlowDatabase.shared
        refreshTransportPolicy()

        installStatusItem()
        Log.app.info("WriterFlow launched")

        permissions.refresh()
        hadAccessibility = permissions.accessibility
        hadInputMonitoring = permissions.inputMonitoring
        applyPermissionState()

        // Register with TCC early so WriterFlow appears in System Settings lists.
        if !permissions.allGranted {
            permissions.registerWithSystem()
            permissions.startPolling()
        }

        // Stay menu-bar-only on cold start and login-at-login. Dashboard opens from
        // the status menu, ⌘,, applicationShouldHandleReopen, or Setup's Account CTA —
        // never automatically, so a background launch does not steal focus.
        dashboardWindow.visibilityDelegate = self
        onboarding.visibilityDelegate = self
        onboarding.onOpenDashboard = { [weak self] in
            self?.dashboardWindow.show()
            NotificationCenter.default.post(name: .openWriterFlowAccount, object: nil)
        }

        #if DEBUG
        // Contributor builds may seed Keychain from local development credentials.
        // Release builds compile this path out completely.
        seedAzureCredentials()
        #endif

        // Permissions gate the floating icon / AI actions — surface setup only when
        // macOS reports them missing and the user has not dismissed Setup.
        if shouldAutoPresentSetup {
            Log.app.info("Permissions incomplete — showing Setup (Dashboard stays closed)")
            onboarding.show()
        }

        focusMonitor.delegate = self

        actionEngine.onStreamDelta = { [weak self] delta in
            self?.overlay.appendVariant(0, delta: delta)
        }
        actionEngine.onStreamVariantDelta = { [weak self] index, delta in
            self?.overlay.appendVariant(index, delta: delta)
        }
        actionEngine.onVariantStreamCompleted = { [weak self] index in
            self?.overlay.markVariantComplete(index)
        }
        actionEngine.onStreamPromptBuilder = { [weak self] prompt in
            self?.overlay.updatePromptBuilderPreview(prompt: prompt)
        }
        actionEngine.onPromptBuilderClarify = { [weak self] questions in
            self?.overlay.showPromptBuilderClarify(questions: questions)
        }
        actionEngine.onCompleted = { [weak self] _, variants, snapshot, event in
            self?.overlay.finishPreview(variants: variants, snapshot: snapshot, event: event)
        }
        actionEngine.onFailed = { [weak self] message in
            self?.overlay.failPreview(message: message)
        }
        actionEngine.onSkillDecision = {
            [weak self] skillID, skillVersion, label, action, outputMode, executionMode in
            self?.overlay.applySkillDecision(
                skillID: skillID,
                skillVersion: skillVersion,
                label: label,
                action: action,
                outputMode: outputMode,
                executionMode: executionMode
            )
        }

        overlay.onCancelRequested = { [weak self] in
            self?.autoActionCoordinator.cancel()
        }
        overlay.onActionSelected = { [weak self] action, field in
            self?.actionEngine.run(action: action, field: field)
        }
        overlay.onCustomActionSelected = { [weak self] instruction, field in
            self?.actionEngine.run(action: .custom, field: field, customInstruction: instruction)
        }
        overlay.onPromptBuilderActionSelected = { [weak self] brief, field in
            self?.actionEngine.run(action: .promptBuilder, field: field, customInstruction: brief)
        }
        overlay.onPromptBuilderAnswersSelected = { [weak self] answers, field in
            self?.actionEngine.finalizePromptBuilder(answers: answers, field: field)
        }
        overlay.onRequestRecommendation = { [weak self] field in
            self?.recommendationEngine.recommend(field: field)
        }
        overlay.onCancelRecommendation = { [weak self] in
            self?.recommendationEngine.cancel()
        }
        overlay.onCheckCachedRecommendation = { [weak self] field in
            self?.recommendationEngine.recommendation(for: field)
        }
        recommendationEngine.onRecommendation = { [weak self] action, field in
            self?.overlay.applyRecommendation(action, for: field)
        }
        overlay.onAutoTrigger = { [weak self] field, directive in
            self?.startPrimaryAction(field: field, directive: directive)
        }
        overlay.onAutoRetry = { [weak self] field, directive, retryOf in
            self?.autoActionCoordinator.retry(field: field, directive: directive, retryOf: retryOf)
        }
        overlay.onAdjustActionSelected = { [weak self] instruction, field, parentID, priorOutput in
            self?.autoActionCoordinator.adjust(
                instruction: instruction,
                field: field,
                parentOperationID: parentID,
                priorOutput: priorOutput
            )
        }
        overlay.onClassifierFeedback = { [weak self] operationID, outcome, appCategory in
            guard let self else { return }
            Task {
                do {
                    let token = try await self.deviceSession.accessToken()
                    try await self.writerFlowAPI.sendInferenceFeedback(
                        operationId: operationID,
                        outcome: outcome,
                        appCategory: appCategory,
                        accessToken: token
                    )
                } catch {
                    Log.engine.notice("Classifier feedback was not recorded")
                }
            }
        }

        naturalLanguageHotkey.onTrigger = { [weak self] in
            guard self?.settings.isPaused == false else { return }
            self?.overlay.openNaturalDirectiveComposer()
        }
        if !settings.isPaused {
            installPrimaryHotkey(combo: settings.hotkeyCombo)
            installNaturalLanguageHotkey(for: settings.hotkeyCombo)
        }

        // Reconcile persisted launch-at-login state with the current SMAppService registration.
        LaunchAtLogin.apply(enabled: settings.launchAtLogin)

        settings.$launchAtLogin
            .dropFirst()
            .sink { LaunchAtLogin.apply(enabled: $0) }
            .store(in: &cancellables)

        settings.$isPaused
            .sink { [weak self] paused in self?.applyPause(paused) }
            .store(in: &cancellables)

        settings.$iconMode
            .sink { [weak self] mode in self?.overlay.iconMode = mode }
            .store(in: &cancellables)

        settings.$hotkeyCombo
            .dropFirst()
            .sink { [weak self] combo in self?.applyHotkeyCombo(combo) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .writerFlowDeviceSessionChanged)
            .sink { [weak self] _ in self?.refreshTransportPolicy() }
            .store(in: &cancellables)

        permissions.$accessibility
            .combineLatest(permissions.$inputMonitoring)
            .dropFirst()
            .sink { [weak self] _ in self?.applyPermissionState() }
            .store(in: &cancellables)

        if !settings.isPaused {
            focusMonitor.start()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    private func refreshTransportPolicy() {
        Task {
            do {
                let token = try await deviceSession.accessToken()
                let flags = try await writerFlowAPI.cohortFlags(accessToken: token)
                TransportPreferences.apply(
                    useCloudInference: flags.useCloudInference,
                    allowByoFallback: flags.allowByoFallback,
                    autoActionEnabled: flags.autoActionEnabled
                )
            } catch {
                // Private-beta default is cloud and fail-closed. A stale or
                // unavailable flag response must never silently expose BYO.
                let autoActionWasEnabled = TransportPreferences.autoActionEnabled
                TransportPreferences.apply(useCloudInference: true, allowByoFallback: false, autoActionEnabled: false)
                if case DeviceSessionError.notPaired = error {
                    // Expected/quiet: nothing to fetch flags with until the user signs in.
                    Log.auth.notice("Cohort flags unavailable; not signed in")
                } else {
                    // Signed in but the flags call itself failed (API unreachable, 5xx,
                    // decode error, ...) — this silently turns off auto-action, so the
                    // user needs to know why rather than just seeing it stop working.
                    Log.auth.error("Cohort flags request failed; using cloud-only default: \(String(describing: error))")
                    if autoActionWasEnabled {
                        ErrorToast.show(
                            "WriterFlow couldn't reach its server just now — auto actions are paused until it reconnects.",
                            style: .info
                        )
                    }
                }
            }
        }
    }

    @objc private func appDidBecomeActive() {
        permissions.refresh()
        applyPermissionState()
    }

    @objc private func systemWillSleep() {
        contextCapsules.clear()
        autoActionCoordinator.cancel()
        overlay.cancelPreview()
    }

    /// `writerflow://paired` (ADR-0011) — foreground hint only. Deliberately
    /// never reads `url.query`/`url.fragment` as anything credential-like;
    /// the only effect is nudging an in-flight pairing poll to check sooner.
    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        // Explicit local-development entry point. This compiles out of the
        // release app and is accepted only while the API resolves to
        // loopback, so a website cannot start production account pairing.
        if urls.contains(where: { $0.scheme == "writerflow" && $0.host == "pair-local" }),
           WriterFlowAPIConfig.isLoopbackAPI(WriterFlowAPIConfig.resolved().baseURL) {
            dashboardWindow.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .openWriterFlowAccount, object: nil)
                NotificationCenter.default.post(name: .beginWriterFlowLocalPairing, object: nil)
            }
            return
        }
        #endif
        guard urls.contains(where: { $0.scheme == "writerflow" && $0.host == "paired" }) else { return }
        Log.auth.info("writerflow://paired foreground hint received")
        NSApp.activate(ignoringOtherApps: true)
        Task { await deviceSession.handleForegroundHint() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardWindow.show()
        return true
    }

    private var shouldAutoPresentSetup: Bool {
        !permissions.allGranted && !SetupPreferences.userDismissedSetup
    }

    func updateActivationPolicy() {
        let needsRegular = dashboardWindow.isVisible || onboarding.isVisible
        let policy: NSApplication.ActivationPolicy = needsRegular ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func applyPermissionState() {
        let axNow = permissions.accessibility
        let imNow = permissions.inputMonitoring

        overlay.iconMode = settings.iconMode

        let ax = axNow ? "✓" : "✗"
        let im = imNow ? "✓" : "✗"
        statusMenuItem?.title = "Permissions — Accessibility \(ax)  Input Monitoring \(im)"

        let axChanged = axNow != hadAccessibility
        let imChanged = imNow != hadInputMonitoring
        if axChanged || imChanged {
            if !axNow {
                Log.app.error("Accessibility not granted — WriterFlow cannot detect text fields")
            }
            if !imNow {
                Log.app.error("Input Monitoring not granted — icon still shows on every focused text field (degraded mode)")
            }
            if permissions.allGranted {
                Log.app.info("All permissions granted")
            }
        }
        if permissions.allGranted {
            permissions.stopPolling()
            if onboarding.isVisible {
                onboarding.close(userInitiated: false)
            }
        }
        if !permissions.allGranted {
            contextCapsules.clear()
        }
        updateActivationPolicy()

        // Event tap / AX observer only succeed when TCC is already granted at install time.
        if !settings.isPaused {
            if (!hadAccessibility && axNow) || (!hadInputMonitoring && imNow) {
                focusMonitor.restart()
                installPrimaryHotkey(combo: settings.hotkeyCombo)
                installNaturalLanguageHotkey(for: settings.hotkeyCombo)
                Log.app.info("Permissions newly granted — restarted focus monitor + hotkey")
            }
        }
        hadAccessibility = axNow
        hadInputMonitoring = imNow
    }

    private func applyPause(_ paused: Bool) {
        pauseMenuItem?.state = paused ? .on : .off
        statusItem?.button?.appearsDisabled = paused
        if paused {
            globalHotkey.uninstall()
            naturalLanguageHotkey.uninstall()
            actionEngine.cancel()
            contextCapsules.clear()
            overlay.dismissActionPopover()
            overlay.cancelPreview()
            focusMonitor.stop()
            Log.app.info("Paused")
        } else {
            installPrimaryHotkey(combo: settings.hotkeyCombo)
            installNaturalLanguageHotkey(for: settings.hotkeyCombo)
            focusMonitor.start()
            Log.app.info("Resumed")
        }
    }

    /// Live-apply for the Settings tab's hotkey recorder — attempts registration immediately;
    /// on OS-level collision (another app already owns that combo), reverts and surfaces why.
    private func applyHotkeyCombo(_ combo: HotkeyCombo) {
        guard !settings.isPaused else { return }
        let previous = globalHotkey.installedCombo ?? combo
        configurePrimaryHotkeyCallback()
        if globalHotkey.install(combo: combo) {
            installNaturalLanguageHotkey(for: combo)
            settings.hotkeyStatusIsError = false
            settings.hotkeyStatusMessage = "Shortcut set to \(combo.displayString)."
        } else {
            settings.hotkeyStatusIsError = true
            settings.hotkeyStatusMessage = "\(combo.displayString) is already in use by another app — reverted to \(previous.displayString)."
            settings.hotkeyCombo = previous
        }
    }

    private func configurePrimaryHotkeyCallback() {
        globalHotkey.onTrigger = { [weak self] in
            guard let self, self.settings.isPaused == false else { return }
            guard let field = self.overlay.activeField else {
                Log.app.notice("Primary hotkey ignored because no editable field is active")
                return
            }
            Log.app.info("Primary hotkey triggered")
            self.startPrimaryAction(field: field, directive: nil)
        }
    }

    private func installPrimaryHotkey(combo: HotkeyCombo) {
        configurePrimaryHotkeyCallback()
        if globalHotkey.install(combo: combo) {
            Log.app.info("Primary hotkey installed: \(combo.displayString, privacy: .public)")
        } else {
            Log.app.error("Primary hotkey registration failed: \(combo.displayString, privacy: .public)")
        }
    }

    private func installNaturalLanguageHotkey(for combo: HotkeyCombo) {
        naturalLanguageHotkey.onTrigger = { [weak self] in
            guard self?.settings.isPaused == false else { return }
            self?.overlay.openNaturalDirectiveComposer()
        }
        let naturalCombo = HotkeyCombo(
            keyCode: combo.keyCode,
            modifiers: combo.modifiers | UInt32(shiftKey)
        )
        if !naturalLanguageHotkey.install(combo: naturalCombo) {
            Log.app.notice("Natural-language hotkey unavailable")
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = WriterFlowIcon.makeNSImage(size: 16)
            button.image?.isTemplate = false
            button.imagePosition = .imageOnly
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause(_:)), keyEquivalent: "p")
        pause.target = self
        pause.state = settings.isPaused ? .on : .off
        pauseMenuItem = pause
        menu.addItem(pause)

        menu.addItem(.separator())

        let status = NSMenuItem(title: "Checking permissions…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        menu.addItem(.separator())

        let onboard = NSMenuItem(title: "Setup…", action: #selector(showOnboarding), keyEquivalent: "")
        onboard.target = self
        menu.addItem(onboard)

        let actions = NSMenuItem(title: "Write with WriterFlow", action: #selector(openActions), keyEquivalent: "")
        actions.keyEquivalentModifierMask = [.control, .option]
        actions.keyEquivalent = " "
        actions.target = self
        menu.addItem(actions)

        // Dashboard hosts History, Personalization, Settings, and Usage — one window,
        // standard ⌘, "preferences" shortcut since Settings lives there now.
        let dashboard = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: ",")
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())

        #if DEBUG
        let quit = NSMenuItem(title: "Quit writeflow_local", action: #selector(quitApp), keyEquivalent: "q")
        #else
        let quit = NSMenuItem(title: "Quit WriterFlow", action: #selector(quitApp), keyEquivalent: "q")
        #endif
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settings.isPaused.toggle()
    }

    @objc private func openActions() {
        guard let field = overlay.activeField else { return }
        startPrimaryAction(field: field, directive: nil)
    }

    private func startPrimaryAction(field: FocusedField, directive: String?) {
        if TransportPreferences.autoActionEnabled {
            autoActionCoordinator.trigger(field: field, directive: directive)
        } else {
            overlay.toggleActionPopover()
        }
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldDidFocus field: FocusedField) {
        overlay.fieldDidFocus(field)
        contextCapsules.focus(field)
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldDidBlur previousBundleID: String?) {
        overlay.fieldDidBlur()
        contextCapsules.clear()
    }

    func focusMonitorTypingStarted(_ monitor: FocusMonitor) {
        overlay.typingStarted()
        if let field = overlay.activeField { contextCapsules.fieldChanged(field) }
    }

    func focusMonitorTypingActivity(_ monitor: FocusMonitor) {
        if let field = overlay.activeField { contextCapsules.fieldChanged(field) }
    }

    func focusMonitorTypingStopped(_ monitor: FocusMonitor) {
        overlay.typingStopped()
    }

    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated field: FocusedField) {
        overlay.fieldFrameUpdated(field)
        // Refresh target geometry without reading field or conversation text.
        contextCapsules.focus(field)
    }

    @objc private func showOnboarding() {
        SetupPreferences.userDismissedSetup = false
        permissions.refresh()
        applyPermissionState()
        onboarding.show()
    }

    @objc private func openDashboard() {
        dashboardWindow.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    #if DEBUG
    private func seedAzureCredentials() {
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let projectEnvURL = DotEnvLoader.findProjectEnvFile(startingAt: exec.deletingLastPathComponent())
        let projectEnv = projectEnvURL.flatMap { DotEnvLoader.load(from: $0) } ?? [:]
        let secretsEnv = DotEnvLoader.load(from: KeychainStore.secretsFileURL) ?? [:]
        var merged = secretsEnv
        for (key, value) in projectEnv where !value.isEmpty {
            merged[key] = value
        }
        KeychainStore.bootstrap(from: merged, keyEnvName: modelsConfig.defaultApiKeyEnv)
    }
    #endif
}

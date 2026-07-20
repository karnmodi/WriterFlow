import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppWindowVisibilityDelegate {
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private let permissions = PermissionsCoordinator()
    private lazy var onboarding = OnboardingWindowController(permissions: permissions, modelsConfig: modelsConfig)
    private lazy var dashboardWindow = DashboardWindowController(modelsConfig: modelsConfig, deviceSession: deviceSession)
    private let focusMonitor = FocusMonitor()
    private let overlay = OverlayController()
    private let globalHotkey = GlobalHotkey()
    private let settings = SettingsStore.shared
    private let modelsConfig = AzureModelsConfig.load()
    // Stage 5.2: device-session state lives in one place, queried via the
    // protocol — not scattered ad hoc Keychain reads through AppDelegate
    // the way the v1 BYO-key readiness check at `needsAzureSetup` below is.
    private let deviceSession: DeviceSessionProviding = DeviceSessionStore()
    private lazy var actionEngine = ActionEngine(config: modelsConfig)
    private lazy var recommendationEngine = RecommendationEngine(config: modelsConfig)
    private var cancellables: Set<AnyCancellable> = []
    private var hadAccessibility = false
    private var hadInputMonitoring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Stage 4.4: bail out early if we relocated to /Applications and are relaunching
        // from there — nothing below should stand up against the DMG-mounted copy.
        AppRelocator.relocateIfNeededFromDMG()

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

        // Dashboard is the default landing surface on every launch — history, personalization,
        // settings, and usage all work without any permission grant (they're local-data screens).
        dashboardWindow.visibilityDelegate = self
        onboarding.visibilityDelegate = self
        onboarding.onOpenDashboard = { [weak self] in self?.dashboardWindow.show() }
        dashboardWindow.show()

        #if DEBUG
        // Contributor builds may seed Keychain from local development credentials.
        // Release builds compile this path out completely.
        seedAzureCredentials()
        #endif

        // Permissions + BYO Azure key gate only the floating icon / AI actions —
        // surface setup on top, non-blocking (Dashboard still works immediately).
        let liveConfig = AzureModelsConfig.loadFromDisk() ?? modelsConfig
        let needsAzureSetup = !KeychainStore.hasConfiguredAPIKey(envName: liveConfig.defaultApiKeyEnv)
            || !liveConfig.hasUsableEndpoint
        if !permissions.allGranted || needsAzureSetup {
            Log.app.info("Setup incomplete — showing onboarding above the Dashboard")
            onboarding.show()
        }

        focusMonitor.delegate = overlay

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

        globalHotkey.onTrigger = { [weak self] in
            guard self?.settings.isPaused == false else { return }
            self?.overlay.toggleActionPopover()
        }
        if !settings.isPaused {
            _ = globalHotkey.install(combo: settings.hotkeyCombo)
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
    }

    @objc private func appDidBecomeActive() {
        permissions.refresh()
        applyPermissionState()
        if !permissions.allGranted {
            onboarding.show()
        }
    }

    /// `writerflow://paired` (ADR-0011) — foreground hint only. Deliberately
    /// never reads `url.query`/`url.fragment` as anything credential-like;
    /// the only effect is nudging an in-flight pairing poll to check sooner.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "writerflow" && $0.host == "paired" }) else { return }
        Log.auth.info("writerflow://paired foreground hint received")
        NSApp.activate(ignoringOtherApps: true)
        Task { await deviceSession.handleForegroundHint() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardWindow.show()
        if !permissions.allGranted {
            onboarding.show()
        }
        return true
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

        if !axNow {
            Log.app.error("Accessibility not granted — WriterFlow cannot detect text fields")
        }
        if !imNow {
            Log.app.error("Input Monitoring not granted — icon shows on field focus (degraded mode)")
        }
        if permissions.allGranted {
            Log.app.info("All permissions granted")
            permissions.stopPolling()
        }
        updateActivationPolicy()

        // Event tap / AX observer only succeed when TCC is already granted at install time.
        if !settings.isPaused {
            if (!hadAccessibility && axNow) || (!hadInputMonitoring && imNow) {
                focusMonitor.restart()
                _ = globalHotkey.install(combo: settings.hotkeyCombo)
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
            actionEngine.cancel()
            overlay.dismissActionPopover()
            focusMonitor.stop()
            Log.app.info("Paused")
        } else {
            _ = globalHotkey.install(combo: settings.hotkeyCombo)
            focusMonitor.start()
            Log.app.info("Resumed")
        }
    }

    /// Live-apply for the Settings tab's hotkey recorder — attempts registration immediately;
    /// on OS-level collision (another app already owns that combo), reverts and surfaces why.
    private func applyHotkeyCombo(_ combo: HotkeyCombo) {
        guard !settings.isPaused else { return }
        let previous = globalHotkey.installedCombo ?? combo
        if globalHotkey.install(combo: combo) {
            settings.hotkeyStatusIsError = false
            settings.hotkeyStatusMessage = "Shortcut set to \(combo.displayString)."
        } else {
            settings.hotkeyStatusIsError = true
            settings.hotkeyStatusMessage = "\(combo.displayString) is already in use by another app — reverted to \(previous.displayString)."
            settings.hotkeyCombo = previous
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

        let actions = NSMenuItem(title: "Open Actions", action: #selector(openActions), keyEquivalent: "")
        actions.keyEquivalentModifierMask = [.control, .option]
        actions.keyEquivalent = " "
        actions.target = self
        menu.addItem(actions)

        // Dashboard hosts History, Personalization, Settings, and Usage — one window,
        // standard ⌘, "preferences" shortcut since Settings lives there now.
        let dashboard = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: ",")
        dashboard.target = self
        menu.addItem(dashboard)

        #if DEBUG
        // Stage 5.2 manual verification only — no production UI trigger exists
        // yet (that's the separate Stage 5.2 "UI" checklist item). Exercises
        // beginPairing()/awaitPairedToken() end to end against whatever
        // WriterFlowAPIConfig.resolved() points at (services/api dev server
        // via WRITERFLOW_API_BASE_URL in .env, or production).
        menu.addItem(.separator())
        let testPairing = NSMenuItem(
            title: "Debug: Test Device Pairing",
            action: #selector(debugTestDevicePairing),
            keyEquivalent: ""
        )
        testPairing.target = self
        menu.addItem(testPairing)
        #endif

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit WriterFlow", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settings.isPaused.toggle()
    }

    @objc private func openActions() {
        overlay.toggleActionPopover()
    }

    @objc private func showOnboarding() {
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
    @objc private func debugTestDevicePairing() {
        Task {
            do {
                let challenge = try await deviceSession.beginPairing()
                Log.auth.info("Pairing started — user_code: \(challenge.userCode, privacy: .public), open: \(challenge.verificationURIComplete.absoluteString, privacy: .public)")
                if NSWorkspace.shared.open(challenge.verificationURIComplete) {
                    Log.auth.info("Opened verification URL in browser")
                } else {
                    Log.auth.error("Could not open verification URL — no /pair page is running yet (expected until the website exists)")
                }
                try await deviceSession.awaitPairedToken()
                let state = await deviceSession.state
                Log.auth.info("Pairing finished — state: \(String(describing: state), privacy: .public)")
            } catch {
                Log.auth.error("Debug pairing failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

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

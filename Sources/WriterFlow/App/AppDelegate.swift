import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private let permissions = PermissionsCoordinator()
    private lazy var onboarding = OnboardingWindowController(permissions: permissions)
    private lazy var dashboardWindow = DashboardWindowController(modelsConfig: modelsConfig)
    private let focusMonitor = FocusMonitor()
    private let overlay = OverlayController()
    private let globalHotkey = GlobalHotkey()
    private let settings = SettingsStore.shared
    private let modelsConfig = AzureModelsConfig.load()
    private lazy var actionEngine = ActionEngine(config: modelsConfig)
    private lazy var recommendationEngine = RecommendationEngine(config: modelsConfig)
    private var cancellables: Set<AnyCancellable> = []
    private var hadAccessibility = false
    private var hadInputMonitoring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        onboarding.onOpenDashboard = { [weak self] in self?.dashboardWindow.show() }
        dashboardWindow.show()

        // Permissions gate only the floating icon/hotkey — surface that setup on top,
        // non-blocking (the user can dismiss it and use the Dashboard immediately).
        if !permissions.allGranted {
            Log.app.info("Permissions missing — showing onboarding above the Dashboard")
            onboarding.show()
        }

        focusMonitor.delegate = overlay

        seedAzureCredentials()

        actionEngine.onStreamDelta = { [weak self] delta in
            self?.overlay.appendPreview(delta)
        }
        actionEngine.onStreamPromptBuilder = { [weak self] prompt in
            self?.overlay.updatePromptBuilderPreview(prompt: prompt)
        }
        actionEngine.onPromptBuilderClarify = { [weak self] questions in
            self?.overlay.showPromptBuilderClarify(questions: questions)
        }
        actionEngine.onCompleted = { [weak self] _, output, snapshot, event in
            self?.overlay.finishPreview(output: output, snapshot: snapshot, event: event)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardWindow.show()
        if !permissions.allGranted {
            onboarding.show()
        }
        return true
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
            NSApp.setActivationPolicy(.accessory)
        }

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

        let onboard = NSMenuItem(title: "Setup Permissions…", action: #selector(showOnboarding), keyEquivalent: "")
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
}

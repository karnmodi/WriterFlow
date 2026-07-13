import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private let permissions = PermissionsCoordinator()
    private lazy var onboarding = OnboardingWindowController(permissions: permissions)
    private let focusMonitor = FocusMonitor()
    private let overlay = OverlayController()
    private let globalHotkey = GlobalHotkey()
    private let settings = SettingsStore.shared
    private let modelsConfig = AzureModelsConfig.load()
    private lazy var actionEngine = ActionEngine(config: modelsConfig)
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        Log.app.info("WriterFlow launched")

        permissions.refresh()
        if !permissions.allGranted {
            Log.app.info("Permissions missing — showing onboarding")
            onboarding.show()
        }

        focusMonitor.delegate = overlay

        seedAzureCredentials()

        actionEngine.onStreamDelta = { delta in
            // Phase 1.4 streams into the preview card; for now log chunks at debug level.
            Log.engine.debug("stream delta len=\(delta.count, privacy: .public)")
        }
        actionEngine.onCompleted = { action, output in
            Log.engine.info(
                "Action complete: \(action.title, privacy: .public) — \(output.prefix(200), privacy: .public)"
            )
        }

        overlay.onActionSelected = { [weak self] action, field in
            self?.actionEngine.run(action: action, field: field)
        }

        globalHotkey.onTrigger = { [weak self] in
            guard self?.settings.isPaused == false else { return }
            self?.overlay.toggleActionPopover()
        }
        if !settings.isPaused {
            _ = globalHotkey.install()
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
            _ = globalHotkey.install()
            focusMonitor.start()
            Log.app.info("Resumed")
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "highlighter",
                accessibilityDescription: "WriterFlow"
            )
            button.image?.isTemplate = true
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

        let onboard = NSMenuItem(title: "Setup Permissions…", action: #selector(showOnboarding), keyEquivalent: "")
        onboard.target = self
        menu.addItem(onboard)

        let dashboard = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit WriterFlow", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settings.isPaused.toggle()
    }

    @objc private func showOnboarding() {
        onboarding.show()
    }

    @objc private func openDashboard() {
        // Dashboard window ships in Phase 3
        Log.app.info("Dashboard requested (stub)")
    }

    @objc private func openSettings() {
        // Settings window ships in Phase 1.5
        Log.app.info("Settings requested (stub)")
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func seedAzureCredentials() {
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent())
        let env = DotEnvLoader.loadMerged(fileURL: envFile)
        KeychainStore.seedFromEnvIfNeeded(env, keyEnvName: modelsConfig.defaultApiKeyEnv)
    }
}

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
    private let settings = SettingsStore.shared
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
            focusMonitor.stop()
            Log.app.info("Paused")
        } else {
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
}

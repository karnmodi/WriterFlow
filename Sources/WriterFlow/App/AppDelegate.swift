import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let permissions = PermissionsCoordinator()
    private lazy var onboarding = OnboardingWindowController(permissions: permissions)
    private let focusMonitor = FocusMonitor()
    private let loggingDelegate = LoggingFocusDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        Log.app.info("WriterFlow launched")

        permissions.refresh()
        if !permissions.allGranted {
            Log.app.info("Permissions missing — showing onboarding")
            onboarding.show()
        }

        focusMonitor.delegate = loggingDelegate
        focusMonitor.start()
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

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
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
        // Wired in Phase 0.5
        sender.state = sender.state == .on ? .off : .on
        Log.app.info("Pause toggled: \(sender.state == .on ? "on" : "off", privacy: .public)")
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

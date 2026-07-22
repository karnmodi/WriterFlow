import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let permissions: PermissionsCoordinator
    private let modelsConfig: AzureModelsConfig
    private(set) var isVisible = false
    weak var visibilityDelegate: AppWindowVisibilityDelegate?
    /// Lets the onboarding screen jump straight to the Dashboard without closing itself first —
    /// the Dashboard is the default landing surface now, onboarding is just an overlay on top of it.
    var onOpenDashboard: (() -> Void)?

    init(permissions: PermissionsCoordinator, modelsConfig: AzureModelsConfig) {
        self.permissions = permissions
        self.modelsConfig = modelsConfig
        super.init()
    }

    func show() {
        if permissions.allGranted {
            return
        }
        if let window {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isVisible = true
            visibilityDelegate?.updateActivationPolicy()
            return
        }

        // Prefer live disk config so Settings edits aren't lost if setup reopens.
        let config = AzureModelsConfig.loadFromDisk() ?? modelsConfig
        let view = OnboardingView(
            permissions: permissions,
            modelsConfig: config,
            onOpenDashboard: { [weak self] in self?.onOpenDashboard?() },
            onDone: { [weak self] in self?.close(userInitiated: true) }
        )

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize, .intrinsicContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.delegate = self
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "WriterFlow — Setup"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 560, height: 720))
        window.minSize = NSSize(width: 560, height: 560)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        isVisible = true
        visibilityDelegate?.updateActivationPolicy()

        // Register with macOS TCC — do NOT open Settings yet (that prevents list registration).
        if !permissions.allGranted {
            permissions.registerWithSystem()
        }
    }

    func close(userInitiated: Bool = true) {
        if userInitiated && !permissions.allGranted {
            SetupPreferences.userDismissedSetup = true
        }
        window?.close()
        window = nil
        isVisible = false
        visibilityDelegate?.updateActivationPolicy()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        isVisible = false
        visibilityDelegate?.updateActivationPolicy()
    }
}

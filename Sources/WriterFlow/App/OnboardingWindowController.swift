import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let permissions: PermissionsCoordinator
    private(set) var isVisible = false
    weak var visibilityDelegate: AppWindowVisibilityDelegate?
    /// Lets the onboarding screen jump straight to the Dashboard without closing itself first —
    /// the Dashboard is the default landing surface now, onboarding is just an overlay on top of it.
    var onOpenDashboard: (() -> Void)?

    init(permissions: PermissionsCoordinator) {
        self.permissions = permissions
        super.init()
    }

    func show() {
        if let window {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isVisible = true
            visibilityDelegate?.updateActivationPolicy()
            return
        }

        let view = OnboardingView(
            permissions: permissions,
            onOpenDashboard: { [weak self] in self?.onOpenDashboard?() },
            onDone: { [weak self] in self?.close() }
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
        window.setContentSize(NSSize(width: 540, height: 640))
        window.minSize = NSSize(width: 540, height: 520)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        isVisible = true
        visibilityDelegate?.updateActivationPolicy()

        // Register with macOS TCC — do NOT open Settings yet (that prevents list registration).
        permissions.registerWithSystem()
    }

    func close() {
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

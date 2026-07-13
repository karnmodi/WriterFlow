import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    let permissions: PermissionsCoordinator

    init(permissions: PermissionsCoordinator) {
        self.permissions = permissions
    }

    func show() {
        // Show dock icon while onboarding so the user can find the app.
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(permissions: permissions) { [weak self] in
            self?.close()
        }

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "WriterFlow — Setup"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window

        // Register with macOS TCC — do NOT open Settings yet (that prevents list registration).
        permissions.registerWithSystem()
    }

    func close() {
        window?.close()
        window = nil
        // Return to invisible menu-bar-only mode once setup is done.
        if permissions.allGranted {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

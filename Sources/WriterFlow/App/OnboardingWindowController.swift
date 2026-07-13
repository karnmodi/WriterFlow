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
        if let window {
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
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
    }
}

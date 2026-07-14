import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private let settingsWindow: SettingsWindowController

    init(settingsWindow: SettingsWindowController) {
        self.settingsWindow = settingsWindow
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DashboardView(settingsWindow: settingsWindow)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "WriterFlow — Dashboard"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

import AppKit
import SwiftUI

@MainActor
protocol AppWindowVisibilityDelegate: AnyObject {
    func updateActivationPolicy()
}

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let modelsConfig: AzureModelsConfig
    private(set) var isVisible = false
    weak var visibilityDelegate: AppWindowVisibilityDelegate?

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isVisible = true
            visibilityDelegate?.updateActivationPolicy()
            return
        }

        let view = DashboardView(modelsConfig: modelsConfig)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "WriterFlow — Dashboard"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        isVisible = true
        visibilityDelegate?.updateActivationPolicy()
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
        visibilityDelegate?.updateActivationPolicy()
    }
}

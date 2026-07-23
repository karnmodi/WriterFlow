import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionsCoordinator: ObservableObject {
    @Published private(set) var accessibility: Bool = false
    @Published private(set) var inputMonitoring: Bool = false

    var allGranted: Bool { accessibility && inputMonitoring }

    private var pollTimer: Timer?

    init() { refresh() }

    func refresh() {
        // Both APIs — some macOS versions only update trust after relaunch.
        let withOptions = AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": false
        ] as CFDictionary)
        let direct = AXIsProcessTrusted()
        let ax = withOptions || direct
        let im = CGPreflightListenEventAccess()

        let axChanged = ax != accessibility
        let imChanged = im != inputMonitoring
        if axChanged { accessibility = ax }
        if imChanged { inputMonitoring = im }

        if axChanged || imChanged {
            Log.app.debug(
                "Permissions refresh ax=\(ax, privacy: .public) im=\(im, privacy: .public) trusted=\(direct, privacy: .public) path=\(AppBundleLocator.appPath, privacy: .public)"
            )
        }
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Register with TCC without opening Settings (call on first launch).
    func registerWithSystem() {
        let axOptionKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([axOptionKey: true] as CFDictionary)
        InputMonitoringProbe.registerWithSystem()
        Log.app.info("Registered with Accessibility + Input Monitoring TCC")
    }

    /// Show Accessibility prompt, then open Settings after a short delay.
    func requestAccessibility() {
        let axOptionKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([axOptionKey: true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    /// Register for Input Monitoring, then open Settings so the user can toggle WriterFlow on.
    func requestInputMonitoring() {
        InputMonitoringProbe.registerWithSystem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }

    /// Reveal WriterFlow.app in Finder and copy its path to the clipboard.
    func revealAppInFinder() {
        AppBundleLocator.revealInFinder()
    }

    /// Steps to re-pair Accessibility after a rebuild (signature/path changed).
    func repairAccessibility() {
        revealAppInFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }

        let alert = NSAlert()
        alert.messageText = "Repair Accessibility"
        alert.informativeText = """
        macOS ties Accessibility to the exact app file. After a rebuild, the toggle can stay ON but WriterFlow won't detect it.

        1. In System Settings → Accessibility, remove WriterFlow (− button)
        2. Click + and select WriterFlow.app (path copied to clipboard / shown in Finder)
        3. Toggle WriterFlow ON
        4. Quit WriterFlow completely (⌘Q), then reopen it

        Tip: run `make install` once — permissions persist better at ~/Applications/WriterFlow.app
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func quitAndRestart() {
        let path = AppBundleLocator.appPath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [path]
        try? task.run()
        NSApp.terminate(nil)
    }

    var appBundlePath: String { AppBundleLocator.displayPath }

    private func openSettings(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}

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
        let axOptionKey = "AXTrustedCheckOptionPrompt"
        let options = [axOptionKey: false] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options)
        inputMonitoring = CGPreflightListenEventAccess()
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

    /// Prompt macOS to show the Accessibility permission dialog and open Settings.
    func requestAccessibility() {
        let axOptionKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([axOptionKey: true] as CFDictionary)
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Prompt macOS to add WriterFlow to Input Monitoring and open Settings.
    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSettings(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}

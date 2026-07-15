import AppKit
import Foundation

/// Stage 4.3 kill-switch: if AX reads/writes fail 3 times in a row for one app,
/// auto-disable WriterFlow for that app for the rest of this launch (icon stops
/// appearing there) rather than repeatedly banging against a broken integration.
/// Session-only — deliberately not persisted, unlike `AppRule.excluded`, which is
/// a durable user choice. A single success resets the streak.
@MainActor
final class AXWatchdog: ObservableObject {
    static let shared = AXWatchdog()

    private static let threshold = 3

    @Published private(set) var disabledBundleIDs: Set<String> = []
    private var consecutiveFailures: [String: Int] = [:]

    private init() {}

    func record(bundleID: String?, ok: Bool) {
        guard let bundleID, !disabledBundleIDs.contains(bundleID) else { return }

        guard !ok else {
            consecutiveFailures[bundleID] = 0
            return
        }

        let count = (consecutiveFailures[bundleID] ?? 0) + 1
        consecutiveFailures[bundleID] = count
        guard count >= Self.threshold else { return }

        consecutiveFailures[bundleID] = 0
        disabledBundleIDs.insert(bundleID)
        Log.engine.error(
            "AXWatchdog: auto-disabled bundleID=\(bundleID, privacy: .public) after \(count, privacy: .public) consecutive AX failures"
        )
        ErrorToast.show(
            "WriterFlow paused for \(Self.displayName(forBundleID: bundleID)) this session — accessibility isn't responding reliably. Re-enable it in Settings."
        )
    }

    func isDisabled(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return disabledBundleIDs.contains(bundleID)
    }

    func reenable(bundleID: String) {
        disabledBundleIDs.remove(bundleID)
        consecutiveFailures[bundleID] = 0
    }

    static func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

import AppKit
import Darwin
import Foundation

/// Stage 4.4: if the user launches WriterFlow straight from the mounted install DMG
/// instead of dragging it to Applications first, offer to do that copy + relaunch —
/// running from a read-only disk image means no writes, no launch-at-login, and the
/// app vanishes the moment the image is ejected.
enum AppRelocator {
    @MainActor
    static func relocateIfNeededFromDMG() {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasPrefix("/Volumes/") else { return }

        let alert = NSAlert()
        alert.messageText = "Move WriterFlow to Applications?"
        alert.informativeText = "WriterFlow is running from the install disk image. Move it to your Applications folder so it keeps working after you eject the image, and so permissions and launch-at-login stay stable across updates."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        let destinationDir = fm.urls(for: .applicationDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/Applications")
        let destination = destinationDir.appendingPathComponent("WriterFlow.app")

        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: URL(fileURLWithPath: bundlePath), to: destination)
            // The copy inherits com.apple.quarantine from the DMG-mounted original;
            // clear it on the relocated copy so the user isn't re-prompted by Gatekeeper
            // for an app they just explicitly asked to install.
            removeQuarantineAttribute(at: destination)
            NSWorkspace.shared.open(destination)
            NSApp.terminate(nil)
        } catch {
            Log.app.error("AppRelocator: copy to Applications failed: \(String(describing: error), privacy: .public)")
            let failure = NSAlert()
            failure.messageText = "Couldn't move automatically"
            failure.informativeText = "Please drag WriterFlow.app into your Applications folder manually, then launch it from there."
            failure.runModal()
        }
    }

    private static func removeQuarantineAttribute(at url: URL) {
        _ = url.path.withCString { path in
            removexattr(path, "com.apple.quarantine", 0)
        }
    }
}

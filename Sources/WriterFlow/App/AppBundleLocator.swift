import AppKit
import Foundation

/// Resolves and reveals the running WriterFlow.app bundle on disk.
enum AppBundleLocator {
    static var appURL: URL {
        Bundle.main.bundleURL
    }

    static var appPath: String {
        appURL.path
    }

    static var displayPath: String {
        // Shorten home directory for readability in the UI.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = appPath
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @MainActor
    static func revealInFinder() {
        let url = appURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.app.error("App bundle not found at \(url.path, privacy: .public)")
            return
        }

        // Select the .app in its parent folder (more reliable than activateFileViewerSelecting alone).
        let parent = url.deletingLastPathComponent().path
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: parent)

        // Bring Finder forward.
        if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.openApplication(
                at: finder,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        Log.app.info("Revealed in Finder + copied path: \(url.path, privacy: .public)")
    }
}

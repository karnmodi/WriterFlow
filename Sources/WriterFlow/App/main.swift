import AppKit
import Darwin
import Foundation

let app = NSApplication.shared

// Release verification invokes the executable directly from the mounted DMG.
// Stop before TCC, Keychain, database, or relocation work while still proving
// dyld can load every dependency, AppKit can initialize, and required bundle
// resources resolve from the packaged .app.
if CommandLine.arguments.contains("--smoke-launch") {
    let resources = Bundle.main.resourceURL
    let requiredResources = ["AppIcon.icns", "THIRD-PARTY-NOTICES.txt"]
    let bundleIsLaunchable = Bundle.main.bundleURL.pathExtension == "app"
        && resources.map { root in
            requiredResources.allSatisfy {
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
            }
        } == true
    exit(bundleIsLaunchable ? EXIT_SUCCESS : EXIT_FAILURE)
}

let delegate = AppDelegate()
app.delegate = delegate
NSApp.setActivationPolicy(.accessory)
app.run()

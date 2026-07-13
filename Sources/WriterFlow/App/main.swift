import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
NSApp.setActivationPolicy(.accessory)
app.run()

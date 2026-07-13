import ApplicationServices
import Foundation

/// Wraps a single app's AXObserver for focused-element changes.
/// Callbacks fire on the main run loop.
final class AppObserver {
    let pid: pid_t
    let bundleID: String?
    private let appElement: AXUIElement
    private var observer: AXObserver?

    /// Fired when the focused UI element changes. `nil` = no focused element.
    var onFocusChanged: ((AXUIElement?) -> Void)?

    init(pid: pid_t, bundleID: String?) {
        self.pid = pid
        self.bundleID = bundleID
        self.appElement = AXUIElementCreateApplication(pid)
    }

    func start() {
        guard observer == nil else { return }

        var created: AXObserver?
        let result = AXObserverCreate(pid, observerCallback, &created)
        guard result == .success, let observer = created else {
            Log.focus.error("AXObserverCreate failed for pid=\(self.pid) result=\(result.rawValue)")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(
            observer,
            appElement,
            AXNotify.focusedUIElementChanged as CFString,
            selfPtr
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = observer

        // Bootstrap: emit the current focused element right now.
        emitCurrentFocus()
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            _ = AXObserverRemoveNotification(
                observer,
                appElement,
                AXNotify.focusedUIElementChanged as CFString
            )
        }
        observer = nil
    }

    /// Set an AX attribute on the app element itself (used for Chrome/Electron quirks).
    func setAppAttribute(_ attribute: String, boolValue: Bool) {
        _ = AXCall.set(appElement, attribute, value: boolValue as CFBoolean)
    }

    private func emitCurrentFocus() {
        let focused = AXCall.element(appElement, AXAttr.focusedUIElement)
        onFocusChanged?(focused)
    }

    fileprivate func handleFocusChanged(element: AXUIElement) {
        onFocusChanged?(element)
    }
}

private func observerCallback(
    observer _: AXObserver,
    element: AXUIElement,
    notification _: CFString,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let this = Unmanaged<AppObserver>.fromOpaque(userInfo).takeUnretainedValue()
    this.handleFocusChanged(element: element)
}

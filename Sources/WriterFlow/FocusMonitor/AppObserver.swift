import ApplicationServices
import Foundation

/// Wraps a single app's AXObserver for focused-element changes.
/// Callbacks fire on the main run loop.
///
/// Observes both the app and the focused window — Notes and other AppKit apps
/// often only emit `AXFocusedUIElementChanged` on the window, not the app root.
final class AppObserver {
    let pid: pid_t
    let bundleID: String?
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var observedWindow: AXUIElement?
    private var observedValueElement: AXUIElement?

    /// Fired when the focused UI element changes. `nil` = no focused element.
    var onFocusChanged: ((AXUIElement?) -> Void)?

    /// Fired when the watched editable element's value or selection changes.
    var onValueChanged: (() -> Void)?

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
        _ = AXObserverAddNotification(
            observer,
            appElement,
            AXNotify.focusedWindowChanged as CFString,
            selfPtr
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = observer

        refreshWindowObservation()
        emitCurrentFocus()
    }

    func stop() {
        clearValueObservation()
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
            _ = AXObserverRemoveNotification(
                observer,
                appElement,
                AXNotify.focusedWindowChanged as CFString
            )
            if let window = observedWindow {
                _ = AXObserverRemoveNotification(
                    observer,
                    window,
                    AXNotify.focusedUIElementChanged as CFString
                )
            }
        }
        observer = nil
        observedWindow = nil
    }

    /// Watch value + selection changes on the focused element (caret moves without typing).
    func observeValueChanges(on element: AXUIElement?) {
        clearValueObservation()
        guard let observer, let element else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        for notify in [AXNotify.valueChanged, AXNotify.selectedTextChanged] {
            let added = AXObserverAddNotification(
                observer,
                element,
                notify as CFString,
                selfPtr
            )
            if added == .success {
                observedValueElement = element
            }
        }
    }

    func setAppAttribute(_ attribute: String, boolValue: Bool) {
        _ = AXCall.set(appElement, attribute, value: boolValue as CFBoolean)
    }

    private func clearValueObservation() {
        if let observer, let element = observedValueElement {
            for notify in [AXNotify.valueChanged, AXNotify.selectedTextChanged] {
                _ = AXObserverRemoveNotification(
                    observer,
                    element,
                    notify as CFString
                )
            }
        }
        observedValueElement = nil
    }

    private func refreshWindowObservation() {
        guard let observer else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        if let previous = observedWindow {
            _ = AXObserverRemoveNotification(
                observer,
                previous,
                AXNotify.focusedUIElementChanged as CFString
            )
            observedWindow = nil
        }

        guard let window = AXCall.element(appElement, AXAttr.focusedWindow) else { return }
        _ = AXObserverAddNotification(
            observer,
            window,
            AXNotify.focusedUIElementChanged as CFString,
            selfPtr
        )
        observedWindow = window
    }

    private func emitCurrentFocus() {
        if let window = AXCall.element(appElement, AXAttr.focusedWindow),
           let focused = AXCall.element(window, AXAttr.focusedUIElement) {
            onFocusChanged?(focused)
            return
        }
        let focused = AXCall.element(appElement, AXAttr.focusedUIElement)
        onFocusChanged?(focused)
    }

    fileprivate func handleNotification(element: AXUIElement, name: CFString) {
        let notify = name as String
        if notify == AXNotify.focusedWindowChanged {
            refreshWindowObservation()
            emitCurrentFocus()
            return
        }
        if notify == AXNotify.focusedUIElementChanged {
            let focused = AXCall.element(element, AXAttr.focusedUIElement) ?? element
            onFocusChanged?(focused)
            return
        }
        if notify == AXNotify.valueChanged || notify == AXNotify.selectedTextChanged {
            onValueChanged?()
        }
    }
}

private func observerCallback(
    observer _: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let this = Unmanaged<AppObserver>.fromOpaque(userInfo).takeUnretainedValue()
    this.handleNotification(element: element, name: notification)
}

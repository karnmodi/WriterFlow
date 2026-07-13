import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Consumes navigation keys while the action popover is open so they never
/// reach the host text field. Separate from the listen-only typing EventTap.
final class PopoverKeyMonitor {
    enum KeyEvent: Sendable {
        case digit(Int)
        case up
        case down
        case escape
        case returnKey
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKey: ((KeyEvent) -> Void)?

    func install() -> Bool {
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: popoverKeyTapCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    func uninstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        runLoopSource = nil
        tap = nil
        onKey = nil
    }

    fileprivate func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        let mapped: KeyEvent? = switch Int(keyCode) {
        case kVK_ANSI_1: .digit(1)
        case kVK_ANSI_2: .digit(2)
        case kVK_ANSI_3: .digit(3)
        case kVK_ANSI_4: .digit(4)
        case kVK_UpArrow: .up
        case kVK_DownArrow: .down
        case kVK_Escape: .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: .returnKey
        default: nil
        }

        guard let mapped else { return false }

        let callback = onKey
        DispatchQueue.main.async {
            callback?(mapped)
        }
        return true
    }

    fileprivate func handleDisabled() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }
}

private func popoverKeyTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<PopoverKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .keyDown:
        if monitor.handleKeyDown(event) {
            return nil
        }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        monitor.handleDisabled()
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

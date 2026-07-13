import CoreGraphics
import Foundation

/// Listen-only CGEventTap over keyDown. Bumps `lastKeystrokeAt`; key contents
/// are never inspected, buffered, or logged.
///
/// The tap fires on the main run loop. macOS may disable the tap under load —
/// we re-enable on `tapDisabledBy*` events.
final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Monotonic nanoseconds of the most recent keyDown, or 0 if none seen.
    /// Read from any thread; written from the tap callback on main.
    nonisolated(unsafe) private(set) var lastKeystrokeMachTime: UInt64 = 0

    /// Called on the main run loop for each keyDown. Keep short — do not do work here.
    var onKeyDown: (() -> Void)?

    func install() -> Bool {
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
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
    }

    fileprivate func handleKeyDown() {
        lastKeystrokeMachTime = mach_absolute_time()
        onKeyDown?()
    }

    fileprivate func handleDisabled() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }
}

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .keyDown:
        tap.handleKeyDown()
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tap.handleDisabled()
    default:
        break
    }

    // `.listenOnly` means our return value is ignored; pass the event through.
    return Unmanaged.passUnretained(event)
}

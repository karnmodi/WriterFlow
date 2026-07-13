import CoreGraphics
import Foundation

/// One-shot event tap attempt so macOS adds WriterFlow to Input Monitoring.
enum InputMonitoringProbe {
    static func registerWithSystem() {
        _ = CGRequestListenEventAccess()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: probeTapCallback,
            userInfo: nil
        ) else {
            Log.app.info("Input Monitoring probe: tap create failed (expected before permission is granted)")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        Log.app.info("Input Monitoring probe: tap created — WriterFlow should appear in Input Monitoring settings")
    }
}

private func probeTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}

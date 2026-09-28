import CoreGraphics
import Foundation

@MainActor
protocol FocusMonitorDelegate: AnyObject {
    func focusMonitor(_ monitor: FocusMonitor, fieldDidFocus field: FocusedField)
    func focusMonitor(_ monitor: FocusMonitor, fieldDidBlur previousBundleID: String?)
    func focusMonitorTypingStarted(_ monitor: FocusMonitor)
    func focusMonitorTypingActivity(_ monitor: FocusMonitor)
    func focusMonitorTypingStopped(_ monitor: FocusMonitor)
    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated field: FocusedField)
}

extension FocusMonitorDelegate {
    func focusMonitorTypingActivity(_ monitor: FocusMonitor) {}
    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated field: FocusedField) {}
}

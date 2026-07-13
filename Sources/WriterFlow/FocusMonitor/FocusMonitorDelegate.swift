import CoreGraphics
import Foundation

@MainActor
protocol FocusMonitorDelegate: AnyObject {
    func focusMonitor(_ monitor: FocusMonitor, fieldDidFocus field: FocusedField)
    func focusMonitor(_ monitor: FocusMonitor, fieldDidBlur previousBundleID: String?)
    func focusMonitorTypingStarted(_ monitor: FocusMonitor)
    func focusMonitorTypingStopped(_ monitor: FocusMonitor)
    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated frame: CGRect)
}

extension FocusMonitorDelegate {
    func focusMonitor(_ monitor: FocusMonitor, fieldFrameUpdated frame: CGRect) {}
}

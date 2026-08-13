import ApplicationServices
import CoreGraphics
import Foundation

/// Stricter rules for when WriterFlow should treat a focused element as a real text input.
enum StrictFieldGate {
    private static let nativeRoles: Set<String> = [
        AXRole.textField,
        AXRole.textArea,
        AXRole.searchField,
        AXRole.comboBox
    ]

    private static let maxWindowAreaFraction: CGFloat = 0.40

    static func allows(
        _ element: AXUIElement,
        pid: pid_t,
        policy: ComposeAppPolicy = .standard
    ) -> Bool {
        guard let role = AXCall.string(element, AXAttr.role) else { return false }
        if role == AXRole.secureTextField { return false }

        guard let axFrame = AXCall.axFrame(element) else { return false }
        let cocoaFrame = AXCoords.toCocoa(axFrame)
        guard CaretEstimator.isUsableFieldFrame(cocoaFrame) else { return false }

        if nativeRoles.contains(role) {
            return true
        }

        if policy == .spreadsheet {
            // Cells only when small + writable; never treat a whole sheet as one field.
            guard role == AXRole.cell || role == AXRole.group else {
                return AXCall.isSettable(element, AXAttr.selectedTextRange)
                    || AXCall.isSettable(element, AXAttr.value)
            }
            return allowsWebLike(element, role: role, axFrame: axFrame, pid: pid, policy: policy)
        }

        return allowsWebLike(element, role: role, axFrame: axFrame, pid: pid, policy: policy)
    }

    private static func allowsWebLike(
        _ element: AXUIElement,
        role: String,
        axFrame: CGRect,
        pid: pid_t,
        policy: ComposeAppPolicy
    ) -> Bool {
        guard role == AXRole.webArea || role == AXRole.group || role == AXRole.cell else {
            return AXCall.isSettable(element, AXAttr.selectedTextRange)
                || AXCall.isSettable(element, AXAttr.value)
        }

        if let maxWidth = policy.maxWebWidth, axFrame.width > maxWidth {
            return false
        }
        if let maxHeight = policy.maxWebHeight, axFrame.height > maxHeight {
            return false
        }

        if policy.enforcesWindowAreaFraction, occupiesTooMuchOfWindow(axFrame: axFrame, pid: pid) {
            return false
        }

        let canWrite = AXCall.isSettable(element, AXAttr.selectedTextRange)
            || AXCall.isSettable(element, AXAttr.value)
        return canWrite
    }

    private static func occupiesTooMuchOfWindow(axFrame: CGRect, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let window = AXCall.element(app, AXAttr.focusedWindow),
              let windowFrame = AXCall.axFrame(window)
        else { return false }

        let fieldArea = max(axFrame.width, 1) * max(axFrame.height, 1)
        let windowArea = max(windowFrame.width, 1) * max(windowFrame.height, 1)
        return fieldArea / windowArea > maxWindowAreaFraction
    }
}

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Decides whether a given AX element counts as a WriterFlow-editable field,
/// and gates out secure/password contexts.
enum FocusedFieldClassifier {
    static let editableRoles: Set<String> = [
        AXRole.textField,
        AXRole.textArea,
        AXRole.comboBox,
        AXRole.searchField,
        AXRole.webArea
    ]

    static let containerRoles: Set<String> = [
        AXRole.group,
        AXRole.cell
    ]

    static func classify(_ element: AXUIElement, pid: pid_t, bundleID: String?) -> FocusedField? {
        if IsSecureEventInputEnabled() { return nil }

        guard let editable = FocusedElementResolver.resolveEditable(from: element) else {
            return nil
        }
        guard StrictFieldGate.allows(editable, pid: pid) else {
            Log.focus.debug("StrictFieldGate rejected \(bundleID ?? "?", privacy: .public)")
            return nil
        }
        guard let role = AXCall.string(editable, AXAttr.role) else { return nil }
        if role == AXRole.secureTextField { return nil }

        let axFrame = AXCall.axFrame(editable) ?? .zero
        let cocoaFrame = AXCoords.toCocoa(axFrame)
        let (anchor, placementMode) = CaretEstimator.placement(for: editable, cocoaFieldFrame: cocoaFrame)
        if placementMode == .fieldCorner {
            Log.focus.debug("Caret fallback fieldCorner for \(bundleID ?? "?", privacy: .public)")
        }
        return FocusedField(
            role: role,
            frame: cocoaFrame,
            anchorRect: anchor,
            appBundleID: bundleID,
            appPID: pid
        )
    }

    static func isEditableElement(_ element: AXUIElement) -> Bool {
        if IsSecureEventInputEnabled() { return false }

        guard let role = AXCall.string(element, AXAttr.role) else { return false }
        if role == AXRole.secureTextField { return false }

        if editableRoles.contains(role) {
            return true
        }

        if containerRoles.contains(role) {
            return hasReadableOrWritableText(element)
        }

        return AXCall.isSettable(element, AXAttr.value)
    }

    private static func hasReadableOrWritableText(_ element: AXUIElement) -> Bool {
        if AXCall.isSettable(element, AXAttr.value) { return true }
        if let text = AXCall.string(element, AXAttr.value), !text.isEmpty { return true }
        if let selected = AXCall.string(element, AXAttr.selectedText), !selected.isEmpty { return true }
        return false
    }

    static func anchorRect(
        for element: AXUIElement,
        fieldAXFrame: CGRect,
        cocoaFieldFrame: CGRect
    ) -> CGRect {
        CaretEstimator.anchorRect(for: element, cocoaFieldFrame: cocoaFieldFrame)
    }
}

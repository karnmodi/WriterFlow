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
        if IsSecureEventInputEnabled() {
            Log.focus.debug("classify: secure event input active, ignoring \(bundleID ?? "?", privacy: .public)")
            return nil
        }

        let rawRole = AXCall.string(element, AXAttr.role) ?? "?"
        guard let editable = FocusedElementResolver.resolveEditable(from: element) else {
            Log.focus.debug("classify: resolveEditable found nothing, rawRole=\(rawRole, privacy: .public) app=\(bundleID ?? "?", privacy: .public)")
            return nil
        }
        guard StrictFieldGate.allows(editable, pid: pid) else {
            let role = AXCall.string(editable, AXAttr.role) ?? "?"
            let frame = AXCall.axFrame(editable) ?? .zero
            Log.focus.debug("StrictFieldGate rejected role=\(role, privacy: .public) frame=\(frame.debugDescription, privacy: .public) app=\(bundleID ?? "?", privacy: .public)")
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
            appPID: pid,
            supportsReplace: !TerminalApps.isTerminal(bundleID: bundleID)
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

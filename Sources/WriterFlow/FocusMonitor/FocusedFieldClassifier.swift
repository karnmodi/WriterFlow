import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Decides whether a given AX element counts as a WriterFlow-editable field,
/// and gates out secure/password contexts.
enum FocusedFieldClassifier {
    /// Roles we consider directly editable.
    static let editableRoles: Set<String> = [
        AXRole.textField,
        AXRole.textArea,
        AXRole.comboBox
    ]

    /// Runs on a background queue (uses AX). Never touches @MainActor state.
    static func classify(_ element: AXUIElement, pid: pid_t, bundleID: String?) -> FocusedField? {
        // Global secure-input guard — password menus, sudo prompt, etc.
        if IsSecureEventInputEnabled() { return nil }

        guard let role = AXCall.string(element, AXAttr.role) else { return nil }
        if role == AXRole.secureTextField { return nil }

        let looksEditable = editableRoles.contains(role) || AXCall.isSettable(element, AXAttr.value)
        guard looksEditable else { return nil }

        let axFrame = AXCall.axFrame(element) ?? .zero
        let cocoaFrame = AXCoords.toCocoa(axFrame)
        return FocusedField(role: role, frame: cocoaFrame, appBundleID: bundleID, appPID: pid)
    }
}

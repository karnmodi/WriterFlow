import ApplicationServices
import CoreGraphics
import Foundation

/// Stable string constants for the AX attributes and roles we touch.
/// Using literals rather than the CFString globals avoids Swift 6
/// concurrency warnings on shared mutable state.
enum AXAttr {
    static let role                 = "AXRole"
    static let value                = "AXValue"
    static let selectedText         = "AXSelectedText"
    static let selectedTextRange    = "AXSelectedTextRange"
    static let position             = "AXPosition"
    static let size                 = "AXSize"
    static let focusedUIElement     = "AXFocusedUIElement"
    static let focusedWindow        = "AXFocusedWindow"
    static let parent               = "AXParent"
    static let children             = "AXChildren"
    static let title                = "AXTitle"
    static let url                  = "AXURL"
    static let frame                = "AXFrame"
    static let enhancedUserInterface = "AXEnhancedUserInterface"
    static let manualAccessibility  = "AXManualAccessibility"
}

enum AXRole {
    static let textField        = "AXTextField"
    static let textArea         = "AXTextArea"
    static let comboBox         = "AXComboBox"
    static let secureTextField  = "AXSecureTextField"
    static let staticText       = "AXStaticText"
    static let window           = "AXWindow"
    static let webArea          = "AXWebArea"
}

enum AXNotify {
    static let focusedUIElementChanged = "AXFocusedUIElementChanged"
    static let focusedWindowChanged    = "AXFocusedWindowChanged"
    static let valueChanged            = "AXValueChanged"
}

/// A snapshot of a focused editable field the FocusMonitor cares about.
struct FocusedField: Equatable, Sendable {
    let role: String
    let frame: CGRect        // in Cocoa/AppKit coords
    let appBundleID: String?
    let appPID: pid_t
}

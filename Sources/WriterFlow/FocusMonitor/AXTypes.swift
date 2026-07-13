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
    static let boundsForRange       = "AXBoundsForRange"
    static let enhancedUserInterface = "AXEnhancedUserInterface"
    static let manualAccessibility  = "AXManualAccessibility"
}

enum AXRole {
    static let textField        = "AXTextField"
    static let textArea         = "AXTextArea"
    static let comboBox         = "AXComboBox"
    static let searchField      = "AXSearchField"
    static let secureTextField  = "AXSecureTextField"
    static let staticText       = "AXStaticText"
    static let window           = "AXWindow"
    static let webArea          = "AXWebArea"
    static let group            = "AXGroup"
    static let cell             = "AXCell"
}

enum AXNotify {
    static let focusedUIElementChanged = "AXFocusedUIElementChanged"
    static let focusedWindowChanged    = "AXFocusedWindowChanged"
    static let valueChanged            = "AXValueChanged"
    static let selectedTextChanged     = "AXSelectedTextChanged"
}

/// A snapshot of a focused editable field the FocusMonitor cares about.
struct FocusedField: Equatable, Sendable {
    let role: String
    let frame: CGRect        // full field bounds in Cocoa/AppKit coords
    let anchorRect: CGRect   // caret/selection line — use for icon placement
    let appBundleID: String?
    let appPID: pid_t
    /// False for apps (terminals) where AX writes aren't safe — Replace is disabled, Copy-only.
    var supportsReplace: Bool = true

    /// Stable identity for async callbacks — frame/caret updates must not invalidate matches.
    func matchesRecommendationTarget(_ other: FocusedField) -> Bool {
        appPID == other.appPID
            && appBundleID == other.appBundleID
            && role == other.role
    }
}

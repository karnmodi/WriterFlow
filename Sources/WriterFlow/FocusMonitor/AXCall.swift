import ApplicationServices
import CoreGraphics
import Foundation

/// Small AX helpers — every call sets a 500 ms per-element messaging timeout,
/// per CLAUDE.md's "AX can hang on busy apps" rule.
enum AXCall {
    /// Configure a 500 ms messaging timeout on a specific element.
    /// Applies to subsequent calls on that same element.
    static func armTimeout(_ element: AXUIElement, seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value
        else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(raw as! AXValue, .cgPoint, &point) { return point }
        return nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value
        else { return nil }
        var sz = CGSize.zero
        if AXValueGetValue(raw as! AXValue, .cgSize, &sz) { return sz }
        return nil
    }

    /// Frame in AX coordinates (origin top-left of primary display).
    static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = point(element, AXAttr.position),
              let sz = size(element, AXAttr.size)
        else { return nil }
        return CGRect(origin: position, size: sz)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        armTimeout(element)
        var flag = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success else {
            return false
        }
        return flag.boolValue
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, value: CFTypeRef) -> Bool {
        armTimeout(element)
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }
}

/// Converts an AX-coordinate rect (origin top-left of primary display,
/// y grows downward) into a Cocoa-coordinate rect (origin bottom-left of
/// primary display, y grows upward).
enum AXCoords {
    static func toCocoa(_ rect: CGRect) -> CGRect {
        // NSScreen.screens is not concurrency-safe from non-main threads.
        // Callers pass frames already read on their AX queue, so we hop briefly.
        let primaryHeight: CGFloat = MainScreenSnapshot.primaryHeight
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

/// Cache the primary screen height (refreshed via NSApplication.didChangeScreenParametersNotification)
/// so background AX threads can convert AX->Cocoa without touching NSScreen.
enum MainScreenSnapshot {
    nonisolated(unsafe) static var primaryHeight: CGFloat = NSScreenPrimaryHeightUnsafe()
}

@inline(__always)
private func NSScreenPrimaryHeightUnsafe() -> CGFloat {
    // Safe to call at process startup on main. For refreshes we'll re-read on main
    // when we receive didChangeScreenParametersNotification.
    return NSScreen.main?.frame.height ?? 1080
}

import AppKit

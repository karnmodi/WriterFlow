import ApplicationServices
import Foundation

extension AXCall {
    /// Read a `CFRange` (AXValue with type `.cfRange`) attribute.
    static func range(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        armTimeout(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value
        else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// Set a `CFRange` attribute (AXValue with type `.cfRange`).
    @discardableResult
    static func setRange(_ element: AXUIElement, _ attribute: String, range: NSRange) -> Bool {
        armTimeout(element)
        var cf = CFRange(location: range.location, length: range.length)
        guard let boxed = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, boxed) == .success
    }

    /// Set a string attribute.
    @discardableResult
    static func setString(_ element: AXUIElement, _ attribute: String, value: String) -> Bool {
        set(element, attribute, value: value as CFString)
    }
}

import Foundation

/// One-shot read of a focused field.
struct FieldSnapshot: Sendable, Equatable {
    /// The complete `AXValue` string. Empty if the field is empty or wasn't readable.
    let fullText: String
    /// The currently selected substring. Empty if there is no selection.
    let selectedText: String
    /// Selection range in UTF-16 code units within `fullText`.
    let selectedRange: NSRange
    /// AX role of the field (e.g. `"AXTextField"`).
    let role: String
    /// Bundle id of the owning app when known.
    let appBundleID: String?

    /// The substring the action should operate on: selection if any, else the full text.
    var actionText: String {
        selectedText.isEmpty ? fullText : selectedText
    }

    /// Range to write the result into: selection if any, else the whole field.
    var actionRange: NSRange {
        if selectedText.isEmpty {
            return NSRange(location: 0, length: (fullText as NSString).length)
        }
        return selectedRange
    }
}

/// Result of writing back through AX.
enum WriteResult: Sendable {
    case selectedTextReplaced
    case fullValueReplaced
    case clipboardPasted
    case failed(String)
}

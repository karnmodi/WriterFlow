import Foundation

/// Normalizes model output before preview/replace.
enum OutputSanitizer {
    static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
    }
}

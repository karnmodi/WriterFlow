import Foundation

/// Lets a Custom instruction ask for a *derivative* artifact — a title, headline, subject
/// line, summary, TL;DR — generated FROM the field's existing content, without that content
/// being destroyed. `Prompts.instruction(for: .custom)` teaches the model to prefix its output
/// with `---INSERT---` when the instruction calls for this; everything else behaves exactly
/// as before (the whole field/selection gets replaced with the output). Only ever applied to
/// `.custom` action output — no other action's prompt ever mentions this marker, so there's no
/// risk of misinterpreting unrelated output as an insert request.
enum CustomOutputParser {
    enum Mode: Sendable, Equatable {
        case replace
        case insertBeforeContent
    }

    static let marker = "---INSERT---"

    /// Streaming-safe: while there isn't yet enough text to know whether the marker is
    /// present, returns `.replace` with an empty string (so the preview shows nothing rather
    /// than flashing raw dashes) — call again as more text streams in.
    static func parse(_ raw: String) -> (mode: Mode, text: String) {
        let trimmedLeading = String(raw.drop { $0 == "\n" || $0 == " " || $0 == "\t" })
        if trimmedLeading.hasPrefix(marker) {
            let rest = trimmedLeading.dropFirst(marker.count)
            return (.insertBeforeContent, rest.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !trimmedLeading.isEmpty, trimmedLeading.count < marker.count, marker.hasPrefix(trimmedLeading) {
            // Still streaming in the marker itself — hold back until we know either way.
            return (.replace, "")
        }
        return (.replace, raw)
    }
}

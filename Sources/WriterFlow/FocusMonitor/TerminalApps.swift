import Foundation

/// Known terminal emulators. AX-wise these expose the entire scrollback as one
/// read-only text blob — there's no safe way to "replace" a range the way a
/// normal text field supports, so WriterFlow reads the current line only and
/// never attempts to write back (Copy-only).
enum TerminalApps {
    static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper"
    ]

    static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// Reduces a full scrollback read to just the current input line.
    static func currentLine(from fullText: String) -> String {
        let lines = fullText.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}

import Foundation

/// Known terminal emulators. AX-wise these expose the entire scrollback as one
/// text blob — WriterFlow reads the current line only and replaces via
/// key injection (`TerminalLineInserter`: Ctrl+U + paste), never AX scrollback write.
enum TerminalApps {
    static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.mitchellh.ghostty",
        "com.github.alacritty",
        "org.alacritty",
        "io.alacritty",
        "com.raphaelamorim.rio"
    ]

    static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if bundleIDs.contains(bundleID) { return true }
        let lower = bundleID.lowercased()
        // Conservative name match for less-common terminal builds.
        if lower.contains("ghostty") || lower.contains("alacritty") || lower.contains("kitty") {
            return true
        }
        return false
    }

    /// Reduces a full scrollback read to just the current input line.
    static func currentLine(from fullText: String) -> String {
        let lines = fullText.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed) }
        }
        return ""
    }
}

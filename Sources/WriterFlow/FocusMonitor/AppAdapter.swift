import Foundation

/// Per-app compatibility: identity for diagnostics, tone bias for prompts,
/// and whether AX-based Replace is safe.
protocol AppAdapter: Sendable {
    /// Site/app label for `CompatibilityMap` diagnostics (e.g. "gmail", "whatsapp").
    func identify(bundleID: String?, windowTitle: String?) -> String?
    /// System-prompt hint biasing Elaborate/Reply tone. Explicit Formal/Casual always override this.
    var toneBias: String { get }
    /// False disables Replace and forces Copy-only (terminals).
    var supportsReplace: Bool { get }
}

extension AppAdapter {
    var supportsReplace: Bool { true }
}

struct GenericAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? { nil }
    var toneBias: String { "General text field — match the draft's register." }
}

/// Gmail/WhatsApp Web/LinkedIn in a browser tab — identified from the window title
/// (title-based rather than URL-host: simpler, and titles reliably carry the site name).
struct BrowserAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? {
        guard let title = windowTitle?.lowercased() else { return nil }
        if title.contains("chatgpt") || title.contains("openai") { return "chatgpt" }
        if title.contains("claude") || title.contains("anthropic") { return "claude" }
        if title.contains("gemini") || title.contains("bard") { return "gemini" }
        if title.contains("copilot") || title.contains("bing chat") { return "copilot" }
        if title.contains("perplexity") { return "perplexity" }
        if title.contains("poe") && (title.contains("poe.com") || title.hasPrefix("poe")) { return "poe" }
        if title.contains("google docs") || title.contains("docs.google") { return "google-docs" }
        if title.contains("gmail") || title.contains("mail.google") { return "gmail" }
        if title.contains("outlook") || title.contains("office 365") { return "outlook" }
        if title.contains("whatsapp") { return "whatsapp-web" }
        if title.contains("linkedin") { return "linkedin" }
        return nil
    }
    var toneBias: String { "Email/web compose — lean slightly formal unless the draft is clearly casual." }
}

struct VSCodeAdapter: AppAdapter {
    private static let knownBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss"
    ]

    func identify(bundleID: String?, windowTitle: String?) -> String? {
        guard let bundleID else { return nil }
        if Self.knownBundleIDs.contains(bundleID) { return "vscode" }
        if bundleID.lowercased().contains("vscode") { return "vscode" }
        return nil
    }

    var toneBias: String {
        "VS Code editor/chat — technical and concise; preserve code fences when present."
    }
}

struct SpreadsheetAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? {
        guard let bundleID else { return nil }
        if bundleID == "com.microsoft.Excel" { return "excel" }
        if bundleID == "com.apple.iWork.Numbers" { return "numbers" }
        return nil
    }

    var toneBias: String {
        "Spreadsheet cell / formula bar — keep the result short; avoid prose unless asked."
    }
}

struct ChatAppAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? {
        guard let bundleID else { return nil }
        if bundleID == "com.tinyspeck.slackmacgap" { return "slack" }
        if bundleID == "net.whatsapp.WhatsApp" { return "whatsapp-desktop" }
        if bundleID.contains("telegram") { return "telegram" }
        return nil
    }
    var toneBias: String { "Chat app — lean casual and concise." }
}

struct NotionAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? {
        bundleID == "notion.id" ? "notion" : nil
    }
    var toneBias: String { "Notes/docs — match the draft's register." }
}

/// Cursor IDE chat — Electron app; bundle id uses the `com.todesktop.*` prefix.
struct CursorAdapter: AppAdapter {
    private static let knownBundleIDs: Set<String> = ["com.todesktop.230313mzl4w4u92"]

    func identify(bundleID: String?, windowTitle: String?) -> String? {
        guard let bundleID else { return nil }
        if Self.knownBundleIDs.contains(bundleID) { return "cursor" }
        if bundleID.hasPrefix("com.todesktop.") { return "cursor" }
        if bundleID.lowercased().contains("cursor") { return "cursor" }
        return nil
    }

    var toneBias: String {
        "Cursor IDE chat — write the next user message in the thread; technical and concise."
    }
}

struct TerminalAdapter: AppAdapter {
    func identify(bundleID: String?, windowTitle: String?) -> String? {
        TerminalApps.isTerminal(bundleID: bundleID) ? "terminal" : nil
    }
    var toneBias: String { "Terminal input — keep it terse; likely a command, commit message, or note." }
    /// Line-scoped key injection (Ctrl+U + paste), not AX scrollback write.
    var supportsReplace: Bool { true }
}

enum AppAdapterRegistry {
    private static let mailAndWeb: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac"
    ]
    private static let electronChat: Set<String> = ["com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp"]

    static func adapter(for bundleID: String?) -> AppAdapter {
        guard let bundleID else { return GenericAdapter() }
        if TerminalApps.isTerminal(bundleID: bundleID) { return TerminalAdapter() }
        if SpreadsheetAdapter().identify(bundleID: bundleID, windowTitle: nil) != nil {
            return SpreadsheetAdapter()
        }
        if CursorAdapter().identify(bundleID: bundleID, windowTitle: nil) != nil { return CursorAdapter() }
        if VSCodeAdapter().identify(bundleID: bundleID, windowTitle: nil) != nil { return VSCodeAdapter() }
        if bundleID == "notion.id" { return NotionAdapter() }
        if electronChat.contains(bundleID) || bundleID.lowercased().contains("telegram") { return ChatAppAdapter() }
        if mailAndWeb.contains(bundleID) { return BrowserAdapter() }
        if bundleID.lowercased().contains("mail") { return BrowserAdapter() }
        return GenericAdapter()
    }

    /// Resolved site label (e.g. "gmail", "linkedin") for prompt biasing and diagnostics.
    static func siteLabel(bundleID: String?, windowTitle: String?) -> String? {
        let candidates: [AppAdapter] = [
            TerminalAdapter(),
            SpreadsheetAdapter(),
            CursorAdapter(),
            VSCodeAdapter(),
            NotionAdapter(),
            ChatAppAdapter(),
            BrowserAdapter(),
            GenericAdapter()
        ]
        for adapter in candidates {
            if let site = adapter.identify(bundleID: bundleID, windowTitle: windowTitle) {
                return site
            }
        }
        return nil
    }

    private static let llmChatSites: Set<String> = [
        "chatgpt", "claude", "gemini", "copilot", "perplexity", "poe", "cursor", "vscode"
    ]

    static func isLLMChatSite(_ site: String?) -> Bool {
        guard let site else { return false }
        return llmChatSites.contains(site)
    }

    /// Tone bias for prompts — site-aware so Docs tabs don't inherit email tone.
    static func toneBias(bundleID: String?, windowTitle: String?) -> String {
        let site = siteLabel(bundleID: bundleID, windowTitle: windowTitle)
        if site == "google-docs" {
            return "Google Docs — match the document's register; preserve structure."
        }
        return adapter(for: bundleID).toneBias
    }
}

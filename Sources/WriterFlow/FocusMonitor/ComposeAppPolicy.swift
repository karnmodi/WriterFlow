import Foundation

/// Per-app compose detection policy. Additive — does not change the default
/// StrictFieldGate limits used by Gmail/Notion/unknown web surfaces.
enum ComposeAppPolicy: Equatable, Sendable {
    /// Default web/native gates (1200×600, 40% window).
    case standard
    /// Cursor / VS Code / chat compose — allow slightly taller inputs only.
    case tallCompose
    /// Google Docs — large writable surface; resolver must still prefer the focused child.
    case documentSurface
    /// Excel / Numbers — native formula bar or small writable cell only.
    case spreadsheet

    /// Max height for web-like candidates under this policy (`nil` = unlimited).
    var maxWebHeight: CGFloat? {
        switch self {
        case .standard: return 600
        case .tallCompose: return 800
        case .documentSurface: return nil
        case .spreadsheet: return 120
        }
    }

    var maxWebWidth: CGFloat? {
        switch self {
        case .standard, .tallCompose: return 1_200
        case .documentSurface: return nil
        case .spreadsheet: return 2_000
        }
    }

    /// Whether the 40%-of-window area rule applies.
    var enforcesWindowAreaFraction: Bool {
        switch self {
        case .standard, .tallCompose, .spreadsheet: return true
        case .documentSurface: return false
        }
    }

    static func resolve(bundleID: String?, windowTitle: String?) -> ComposeAppPolicy {
        if isSpreadsheet(bundleID) { return .spreadsheet }
        if isDocumentSurface(bundleID: bundleID, windowTitle: windowTitle) { return .documentSurface }
        if isTallCompose(bundleID) { return .tallCompose }
        return .standard
    }

    private static let tallComposeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp",
        "notion.id"
    ]

    private static func isTallCompose(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if tallComposeBundleIDs.contains(bundleID) { return true }
        if bundleID.hasPrefix("com.todesktop.") { return true }
        let lower = bundleID.lowercased()
        if lower.contains("cursor") { return true }
        if lower.contains("telegram") { return true }
        return false
    }

    private static func isSpreadsheet(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.microsoft.Excel"
            || bundleID == "com.apple.iWork.Numbers"
    }

    private static func isDocumentSurface(bundleID: String?, windowTitle: String?) -> Bool {
        let browsers: Set<String> = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac"
        ]
        guard let bundleID, browsers.contains(bundleID) else { return false }
        let title = windowTitle?.lowercased() ?? ""
        return title.contains("google docs")
            || title.contains("docs.google")
            || (title.contains(" - google docs"))
            || (title.hasSuffix("google docs"))
    }
}

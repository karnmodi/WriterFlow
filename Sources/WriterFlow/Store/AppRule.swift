import Foundation
import GRDB

/// Per-app/site tone, signature, and instruction override — edited in the
/// Phase 3 Personalization tab, seeded from Phase 2's `AppAdapter` defaults.
struct AppRule: Codable, Sendable, FetchableRecord, PersistableRecord {
    var bundleOrSite: String
    var tone: String?
    var signature: String?
    var customInstruction: String?
    var excluded: Bool
    /// Stage 4.1 per-app override of the global "Always paste via clipboard" setting.
    /// `nil` = inherit the global default (try AX, fall back to clipboard on failure);
    /// `true` = always paste via clipboard for this app; `false` = never use clipboard
    /// paste for this app, fail loudly instead if AX write doesn't work.
    var clipboardFallback: Bool?

    static let databaseTableName = "app_rules"

    init(
        bundleOrSite: String,
        tone: String? = nil,
        signature: String? = nil,
        customInstruction: String? = nil,
        excluded: Bool = false,
        clipboardFallback: Bool? = nil
    ) {
        self.bundleOrSite = bundleOrSite
        self.tone = tone
        self.signature = signature
        self.customInstruction = customInstruction
        self.excluded = excluded
        self.clipboardFallback = clipboardFallback
    }
}

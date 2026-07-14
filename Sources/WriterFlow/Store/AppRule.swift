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

    static let databaseTableName = "app_rules"

    init(
        bundleOrSite: String,
        tone: String? = nil,
        signature: String? = nil,
        customInstruction: String? = nil,
        excluded: Bool = false
    ) {
        self.bundleOrSite = bundleOrSite
        self.tone = tone
        self.signature = signature
        self.customInstruction = customInstruction
        self.excluded = excluded
    }
}

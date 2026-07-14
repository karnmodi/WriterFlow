import Foundation
import GRDB

/// A personalization fact/style/snippet note — edited in the Phase 3 Personalization tab.
struct MemoryNote: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    enum Kind: String, Codable, Sendable {
        case style
        case fact
        case snippet
    }

    let id: String
    var kind: Kind
    var text: String
    var enabled: Bool
    var updatedAt: Date

    static let databaseTableName = "memory_notes"

    init(kind: Kind, text: String, enabled: Bool = true) {
        self.id = UUID().uuidString
        self.kind = kind
        self.text = text
        self.enabled = enabled
        self.updatedAt = Date()
    }
}

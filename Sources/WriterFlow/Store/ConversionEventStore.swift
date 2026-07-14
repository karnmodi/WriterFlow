import Foundation
import GRDB

struct ConversionEvent: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    /// Stored as `UUID().uuidString` — kept as `String` (not `UUID`) so the
    /// `conversions.id` column is human-readable text, not a GRDB UUID blob.
    let id: String
    let timestamp: Date
    let appBundleID: String?
    var site: String?
    let action: String
    let input: String
    var output: String
    var accepted: Bool
    var model: String?
    var tokensIn: Int?
    var tokensOut: Int?
    var latencyMs: Int?

    static let databaseTableName = "conversions"

    init(
        appBundleID: String?,
        site: String? = nil,
        action: WritingAction,
        input: String,
        output: String = "",
        accepted: Bool = false,
        model: String? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        latencyMs: Int? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.appBundleID = appBundleID
        self.site = site
        self.action = action.title
        self.input = input
        self.output = output
        self.accepted = accepted
        self.model = model
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.latencyMs = latencyMs
    }

    /// Decodes a line from the pre-GRDB `conversions.jsonl` log (Phase 1/2).
    /// Those entries predate site/model/token tracking, so those fields are nil.
    fileprivate init(legacyJSONLine data: Data, decoder: JSONDecoder) throws {
        struct Legacy: Decodable {
            let id: UUID
            let timestamp: Date
            let appBundleID: String?
            let action: String
            let input: String
            let output: String
            let accepted: Bool
        }
        let legacy = try decoder.decode(Legacy.self, from: data)
        self.id = legacy.id.uuidString
        self.timestamp = legacy.timestamp
        self.appBundleID = legacy.appBundleID
        self.site = nil
        self.action = legacy.action
        self.input = legacy.input
        self.output = legacy.output
        self.accepted = legacy.accepted
        self.model = nil
        self.tokensIn = nil
        self.tokensOut = nil
        self.latencyMs = nil
    }
}

/// GRDB-backed history store (Stage 3.1). Replaces Phase 1/2's append-only
/// `conversions.jsonl` log — that file is migrated into the `conversions`
/// table on first launch, then renamed to `conversions.jsonl.migrated`.
actor ConversionEventStore {
    static let shared = ConversionEventStore()

    private let db: DatabaseQueue
    private var didMigrateLegacyLog = false

    init(db: DatabaseQueue = WriterFlowDatabase.shared) {
        self.db = db
    }

    func append(_ event: ConversionEvent) async {
        await migrateLegacyLogIfNeeded()
        do {
            try await db.write { db in
                try event.insert(db)
            }
            Log.store.info("ConversionEvent logged action=\(event.action, privacy: .public)")
        } catch {
            Log.store.error("ConversionEvent insert failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes conversions older than `retentionDays`. Pass `nil` (or a
    /// non-positive value) to keep everything.
    func purgeExpired(retentionDays: Int?) async {
        guard let retentionDays, retentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        do {
            try await db.write { db in
                _ = try ConversionEvent
                    .filter(Column("timestamp") < cutoff)
                    .deleteAll(db)
            }
        } catch {
            Log.store.error("ConversionEvent purge failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Most recent accepted outputs, for Stage 3.3's explicit "Analyze my writing style" pass.
    func recentAcceptedOutputs(limit: Int) async -> [String] {
        do {
            return try await db.read { db in
                try ConversionEvent
                    .filter(Column("accepted") == true)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
                    .map(\.output)
                    .filter { !$0.isEmpty }
            }
        } catch {
            Log.store.error("ConversionEvent recentAcceptedOutputs failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func deleteAll() async {
        do {
            try await db.write { db in
                _ = try ConversionEvent.deleteAll(db)
            }
        } catch {
            Log.store.error("ConversionEvent deleteAll failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Idempotent — safe to call eagerly at launch and again before the first
    /// `append()`, whichever comes first.
    func migrateLegacyLogIfNeeded() async {
        guard !didMigrateLegacyLog else { return }
        didMigrateLegacyLog = true

        let legacyURL = AzureModelsConfig.appSupportURL.appendingPathComponent("conversions.jsonl")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let contents = try? String(contentsOf: legacyURL, encoding: .utf8)
        else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        let migrated: Int
        do {
            migrated = try await db.write { db in
                var count = 0
                for line in lines {
                    guard let data = String(line).data(using: .utf8),
                          let event = try? ConversionEvent(legacyJSONLine: data, decoder: decoder)
                    else { continue }
                    try event.insert(db)
                    count += 1
                }
                return count
            }
        } catch {
            Log.store.error("Legacy conversions.jsonl migration failed: \(String(describing: error), privacy: .public)")
            return
        }

        let migratedURL = legacyURL.appendingPathExtension("migrated")
        try? FileManager.default.removeItem(at: migratedURL)
        try? FileManager.default.moveItem(at: legacyURL, to: migratedURL)
        Log.store.info("Migrated \(migrated, privacy: .public) legacy conversion(s) into writerflow.db")
    }
}

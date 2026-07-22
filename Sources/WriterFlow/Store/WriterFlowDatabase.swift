import Foundation
import GRDB

/// Central GRDB connection for history, memory notes, and per-app rules.
/// One `DatabaseQueue` for the whole app — GRDB serializes writes internally.
enum WriterFlowDatabase {
    /// On open/migration failure this still returns an in-memory queue as a
    /// last resort — so the app can keep running rather than crashing
    /// outright — but it is no longer a *silent* fallback (Stage 5.3 "Store
    /// refactor"): `LaunchCoordinator.shared.state` flips to `.failed` with
    /// a human-readable message, which `DashboardView` surfaces as a banner.
    /// Nothing written to that in-memory queue this session is ever
    /// persisted to disk.
    static let shared: DatabaseQueue = {
        do {
            try FileManager.default.createDirectory(
                at: AzureModelsConfig.appSupportURL,
                withIntermediateDirectories: true
            )
            let url = AzureModelsConfig.appSupportURL.appendingPathComponent("writerflow.db")
            let queue = try DatabaseQueue(path: url.path)
            try migrator.migrate(queue)
            Task { @MainActor in LaunchCoordinator.shared.reportReady() }
            return queue
        } catch {
            Log.store.fault("WriterFlowDatabase failed to open — this session's data will NOT be saved to disk: \(String(describing: error), privacy: .public)")
            let message = "Could not open your local WriterFlow data (\(error.localizedDescription)). History and personalization changes this session will not be saved."
            Task { @MainActor in LaunchCoordinator.shared.reportFailure(message) }
            let queue = try! DatabaseQueue()
            try! migrator.migrate(queue)
            return queue
        }
    }()

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "conversions") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("appBundleID", .text)
                t.column("site", .text)
                t.column("action", .text).notNull()
                t.column("input", .text).notNull()
                t.column("output", .text).notNull()
                t.column("accepted", .boolean).notNull().defaults(to: false)
                t.column("model", .text)
                t.column("tokensIn", .integer)
                t.column("tokensOut", .integer)
                t.column("latencyMs", .integer)
            }
            try db.create(index: "idx_conversions_timestamp", on: "conversions", columns: ["timestamp"])

            try db.create(table: "memory_notes") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "app_rules") { t in
                t.column("bundleOrSite", .text).primaryKey()
                t.column("tone", .text)
                t.column("signature", .text)
                t.column("customInstruction", .text)
                t.column("excluded", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2_clipboard_fallback_override") { db in
            try db.alter(table: "app_rules") { t in
                t.add(column: "clipboardFallback", .boolean)
            }
        }

        return migrator
    }
}

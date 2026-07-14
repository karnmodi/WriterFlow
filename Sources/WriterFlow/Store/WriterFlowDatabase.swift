import Foundation
import GRDB

/// Central GRDB connection for history, memory notes, and per-app rules.
/// One `DatabaseQueue` for the whole app — GRDB serializes writes internally.
enum WriterFlowDatabase {
    static let shared: DatabaseQueue = {
        do {
            try FileManager.default.createDirectory(
                at: AzureModelsConfig.appSupportURL,
                withIntermediateDirectories: true
            )
            let url = AzureModelsConfig.appSupportURL.appendingPathComponent("writerflow.db")
            let queue = try DatabaseQueue(path: url.path)
            try migrator.migrate(queue)
            return queue
        } catch {
            Log.store.error("WriterFlowDatabase failed to open, falling back to in-memory: \(String(describing: error), privacy: .public)")
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

        return migrator
    }
}

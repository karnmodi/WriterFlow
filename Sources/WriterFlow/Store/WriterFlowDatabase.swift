import Foundation
import GRDB

enum WriterFlowDatabaseError: Error, LocalizedError {
    case integrityCheckFailed(String)
    case migrationExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .integrityCheckFailed(let detail):
            return "Encrypted database integrity check failed (\(detail))."
        case .migrationExportFailed(let detail):
            return "Could not migrate local data to encryption (\(detail))."
        }
    }
}

/// Central GRDB connection for history, memory notes, and per-app rules.
/// One `DatabaseQueue` for the whole app — GRDB serializes writes internally.
enum WriterFlowDatabase {
    static let plaintextFileName = "writerflow.db"
    static let encryptedFileName = "writerflow.enc.db"

    /// On open/migration failure this traps after reporting `.failed` to
    /// `LaunchCoordinator` — there is no silent in-memory fallback (Stage 5.3).
    static let shared: DatabaseQueue = {
        do {
            return try openProductionDatabase(reportToLaunchCoordinator: true)
        } catch {
            Log.store.fault(
                "WriterFlowDatabase failed to open: \(String(describing: error), privacy: .public)"
            )
            let message =
                "Could not open your local WriterFlow data (\(error.localizedDescription)). " +
                "History and personalization will not be available this session."
            Task { @MainActor in LaunchCoordinator.shared.reportFailure(message) }
            preconditionFailure(message)
        }
    }()

    // MARK: - Production open

    static func openProductionDatabase(reportToLaunchCoordinator: Bool) throws -> DatabaseQueue {
        AccountDatabaseScope.syncBindingFromDeviceSessionDefaults()

        let fileManager = FileManager.default
        let appSupport = AzureModelsConfig.appSupportURL
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let scope = AccountDatabaseScope.currentDatabaseKeyScope
        let key = DatabaseKeychain.keyOrCreate(scope: scope)
        let passphraseHex = hexPassphrase(from: key)

        let plaintextURL = appSupport.appendingPathComponent(plaintextFileName)
        let encryptedURL = appSupport.appendingPathComponent(encryptedFileName)

        let queue: DatabaseQueue
        if fileManager.fileExists(atPath: encryptedURL.path) {
            queue = try openEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        } else if fileManager.fileExists(atPath: plaintextURL.path) {
            try migratePlaintextToEncrypted(
                plaintextURL: plaintextURL,
                encryptedURL: encryptedURL,
                passphraseHex: passphraseHex,
                fileManager: fileManager
            )
            queue = try openEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        } else {
            queue = try createEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        }

        try migrator.migrate(queue)
        if reportToLaunchCoordinator {
            Task { @MainActor in LaunchCoordinator.shared.reportReady() }
        }
        return queue
    }

    /// Seeds a legacy plaintext database for migration tests.
    static func seedPlaintextDatabase(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memory_notes (id, kind, text, enabled, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: ["legacy-1", "rule", "migrated note", true, Date()]
            )
        }
        try queue.close()
    }

    // MARK: - Test / diagnostic entry points

    /// Opens an isolated encrypted database under `baseDirectory` — used by
    /// unit tests so production Application Support is never touched.
    static func openForTesting(
        baseDirectory: URL,
        scope: String?,
        seedPlaintext: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DatabaseQueue {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let key = DatabaseKeychain.keyOrCreate(scope: scope)
        let passphraseHex = hexPassphrase(from: key)
        let encryptedURL = baseDirectory.appendingPathComponent(encryptedFileName)

        let queue: DatabaseQueue
        if let seedPlaintext {
            let localPlain = baseDirectory.appendingPathComponent(plaintextFileName)
            if fileManager.fileExists(atPath: localPlain.path) {
                try fileManager.removeItem(at: localPlain)
            }
            try fileManager.copyItem(at: seedPlaintext, to: localPlain)
            try migratePlaintextToEncrypted(
                plaintextURL: localPlain,
                encryptedURL: encryptedURL,
                passphraseHex: passphraseHex,
                fileManager: fileManager
            )
            queue = try openEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        } else if fileManager.fileExists(atPath: encryptedURL.path) {
            queue = try openEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        } else {
            queue = try createEncrypted(at: encryptedURL, passphraseHex: passphraseHex)
        }

        try migrator.migrate(queue)
        return queue
    }

    // MARK: - SQLCipher helpers

    static func hexPassphrase(from key: Data) -> String {
        precondition(key.count == 32, "database key must be 256 bits")
        return key.map { String(format: "%02x", $0) }.joined()
    }

    static func makeConfiguration(passphraseHex: String) -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase(passphraseHex)
        }
        return config
    }

    private static func openEncrypted(at url: URL, passphraseHex: String) throws -> DatabaseQueue {
        try DatabaseQueue(path: url.path, configuration: makeConfiguration(passphraseHex: passphraseHex))
    }

    private static func createEncrypted(at url: URL, passphraseHex: String) throws -> DatabaseQueue {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return try openEncrypted(at: url, passphraseHex: passphraseHex)
    }

    private static func verifyCipherIntegrity(_ queue: DatabaseQueue) throws {
        try queue.read { db in
            guard let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version"),
                  !cipherVersion.isEmpty else {
                throw WriterFlowDatabaseError.integrityCheckFailed("SQLCipher is not linked")
            }
            let integrity = try String.fetchOne(db, sql: "PRAGMA cipher_integrity_check")
            if let integrity, !integrity.isEmpty, integrity.caseInsensitiveCompare("ok") != .orderedSame {
                throw WriterFlowDatabaseError.integrityCheckFailed(integrity)
            }
        }
    }

    private static func migratePlaintextToEncrypted(
        plaintextURL: URL,
        encryptedURL: URL,
        passphraseHex: String,
        fileManager: FileManager
    ) throws {
        let migratingURL = encryptedURL.deletingLastPathComponent()
            .appendingPathComponent("\(encryptedFileName).migrating")

        try? fileManager.removeItem(at: migratingURL)

        let source = try DatabaseQueue(path: plaintextURL.path)
        try migrator.migrate(source)

        do {
            try source.write { db in
                try db.execute(
                    sql: """
                        ATTACH DATABASE ? AS encrypted KEY ?;
                        SELECT sqlcipher_export('encrypted');
                        """,
                    arguments: [migratingURL.path, passphraseHex]
                )
            }
        } catch {
            try? source.close()
            try? fileManager.removeItem(at: migratingURL)
            throw WriterFlowDatabaseError.migrationExportFailed(error.localizedDescription)
        }
        try source.close()

        let encrypted = try openEncrypted(at: migratingURL, passphraseHex: passphraseHex)
        defer { try? encrypted.close() }

        try verifyCipherIntegrity(encrypted)
        try migrator.migrate(encrypted)

        let backupURL = plaintextURL.deletingPathExtension()
            .appendingPathExtension("db.plaintext-backup")
        try? fileManager.removeItem(at: backupURL)

        if fileManager.fileExists(atPath: encryptedURL.path) {
            try fileManager.removeItem(at: encryptedURL)
        }
        try fileManager.moveItem(at: migratingURL, to: encryptedURL)
        try fileManager.moveItem(at: plaintextURL, to: backupURL)

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: plaintextURL.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
    }

    // MARK: - Schema

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

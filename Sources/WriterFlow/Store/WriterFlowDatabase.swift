import AppKit
import Foundation
import GRDB

@MainActor
private func showDatabaseRecovery(_ message: String) -> Bool {
    LaunchCoordinator.shared.reportRecoveryRequired(message)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Local data is locked"
    alert.informativeText = message
    alert.addButton(withTitle: "Retry")
    alert.addButton(withTitle: "Quit WriterFlow")
    return alert.runModal() == .alertFirstButtonReturn
}

enum WriterFlowDatabaseError: Error, LocalizedError {
    case missingKey
    case integrityCheckFailed(String)
    case migrationExportFailed(String)
    case accountStorageConflict

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "The encryption key is unavailable. Unlock your login Keychain and retry."
        case .integrityCheckFailed(let detail):
            return "Encrypted database integrity check failed (\(detail))."
        case .migrationExportFailed(let detail):
            return "Could not migrate local data to encryption (\(detail))."
        case .accountStorageConflict:
            return "WriterFlow found both legacy and account-scoped local data. Contact support before continuing."
        }
    }
}

/// Central GRDB connection for history, memory notes, and per-app rules.
/// One `DatabaseQueue` for the whole app — GRDB serializes writes internally.
enum WriterFlowDatabase {
    static let plaintextFileName = "writerflow.db"
    static let encryptedFileName = "writerflow.enc.db"
    static let rollbackFileName = "writerflow.rollback.enc.db"
    private static let rollbackKeyScope = "migration-rollback"

    /// Open failures never create an empty replacement database. The user may
    /// unlock Keychain and retry, or quit without modifying local data.
    static let shared: DatabaseQueue = {
        while true {
            do {
                return try openProductionDatabase(reportToLaunchCoordinator: true)
            } catch {
                Log.store.fault(
                    "WriterFlowDatabase failed to open: \(String(describing: error), privacy: .public)"
                )
                if restoreLegacyBackupIfExplicitlyRequested(after: error) {
                    continue
                }
                let message =
                    "WriterFlow could not unlock your encrypted local data.\n\n" +
                    "\(error.localizedDescription)\n\n" +
                    "No empty database was created and your existing data was not changed."
                let retry = MainActor.assumeIsolated {
                    showDatabaseRecovery(message)
                }
                if !retry {
                    exit(EXIT_FAILURE)
                }
            }
        }
    }()

    // MARK: - Production open

    static func openProductionDatabase(reportToLaunchCoordinator: Bool) throws -> DatabaseQueue {
        AccountDatabaseScope.syncBindingFromDeviceSessionDefaults()

        let fileManager = FileManager.default
        let appSupport = AzureModelsConfig.appSupportURL
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let scope = AccountDatabaseScope.currentDatabaseKeyScope
        let storageDirectory = try accountStorageDirectory(
            appSupport: appSupport,
            scope: scope,
            fileManager: fileManager
        )
        let plaintextURL = storageDirectory.appendingPathComponent(plaintextFileName)
        let encryptedURL = storageDirectory.appendingPathComponent(encryptedFileName)
        let hasEncryptedDatabase = fileManager.fileExists(atPath: encryptedURL.path)
        if hasEncryptedDatabase,
           DatabaseKeychain.read(scope: scope) == nil,
           let scope {
            _ = DatabaseKeychain.bindUnscopedKey(to: scope)
        }
        let key: Data
        if hasEncryptedDatabase {
            guard let existing = DatabaseKeychain.read(scope: scope) else {
                throw WriterFlowDatabaseError.missingKey
            }
            key = existing
        } else {
            key = DatabaseKeychain.keyOrCreate(scope: scope)
        }

        do {
            return try finishProductionOpen(
                key: key,
                plaintextURL: plaintextURL,
                encryptedURL: encryptedURL,
                fileManager: fileManager,
                appSupport: storageDirectory,
                reportToLaunchCoordinator: reportToLaunchCoordinator
            )
        } catch {
            // Account-scoped Keychain item can diverge from the pre-sign-in
            // `unscoped` key that actually encrypted the on-disk file. Repair
            // in place — never mint a replacement database.
            guard hasEncryptedDatabase,
                  let scope,
                  let unscoped = DatabaseKeychain.read(scope: nil),
                  unscoped != key,
                  DatabaseKeychain.repairAccountKeyFromUnscoped(scope: scope) else {
                throw error
            }
            Log.store.notice(
                "Repaired account-scoped database key from unscoped Keychain item after unlock failure"
            )
            return try finishProductionOpen(
                key: unscoped,
                plaintextURL: plaintextURL,
                encryptedURL: encryptedURL,
                fileManager: fileManager,
                appSupport: storageDirectory,
                reportToLaunchCoordinator: reportToLaunchCoordinator
            )
        }
    }

    /// Moves the one legacy v1 database into `accounts/<identity-hash>` on
    /// the first launch after account binding. No copy is deleted: a conflict
    /// fails closed so support can recover both files.
    static func accountStorageDirectory(
        appSupport: URL,
        scope: String?,
        fileManager: FileManager
    ) throws -> URL {
        guard let scope, !scope.isEmpty else { return appSupport }

        let accountsDirectory = appSupport.appendingPathComponent("accounts", isDirectory: true)
        let scopedDirectory = accountsDirectory.appendingPathComponent(scope, isDirectory: true)
        let legacyEncrypted = appSupport.appendingPathComponent(encryptedFileName)
        let scopedEncrypted = scopedDirectory.appendingPathComponent(encryptedFileName)
        let hasLegacy = fileManager.fileExists(atPath: legacyEncrypted.path)
        let hasScoped = fileManager.fileExists(atPath: scopedEncrypted.path)
        if hasLegacy && hasScoped {
            throw WriterFlowDatabaseError.accountStorageConflict
        }

        try fileManager.createDirectory(at: scopedDirectory, withIntermediateDirectories: true)
        if hasLegacy {
            for fileName in [
                "\(encryptedFileName)-wal",
                "\(encryptedFileName)-shm",
                plaintextFileName,
                rollbackFileName,
                // Move the main database last. Its presence is the commit
                // marker, so an interrupted migration resumes sidecars first.
                encryptedFileName
            ] {
                let source = appSupport.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = scopedDirectory.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: destination.path) {
                    throw WriterFlowDatabaseError.accountStorageConflict
                }
                try fileManager.moveItem(at: source, to: destination)
            }
        } else {
            let legacyPlaintext = appSupport.appendingPathComponent(plaintextFileName)
            if fileManager.fileExists(atPath: legacyPlaintext.path) {
                try fileManager.moveItem(
                    at: legacyPlaintext,
                    to: scopedDirectory.appendingPathComponent(plaintextFileName)
                )
            }
        }
        return scopedDirectory
    }

    private static func finishProductionOpen(
        key: Data,
        plaintextURL: URL,
        encryptedURL: URL,
        fileManager: FileManager,
        appSupport: URL,
        reportToLaunchCoordinator: Bool
    ) throws -> DatabaseQueue {
        let passphraseHex = hexPassphrase(from: key)

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

        try verifyCipherIntegrity(queue)
        try migrator.migrate(queue)
        if fileManager.fileExists(atPath: encryptedURL.path) {
            try? fileManager.removeItem(at: plaintextURL)
            let legacyBackupURL = plaintextURL.deletingPathExtension()
                .appendingPathExtension("db.plaintext-backup")
            try? fileManager.removeItem(at: legacyBackupURL)
        }
        cleanupExpiredRollback(in: appSupport, fileManager: fileManager)
        if reportToLaunchCoordinator {
            Task { @MainActor in LaunchCoordinator.shared.reportReady() }
        }
        return queue
    }

    /// Support-only recovery for the plaintext backup created by the early
    /// SQLCipher integration. It runs only under an explicit environment flag;
    /// normal launches keep the blocking recovery UI and never overwrite data.
    private static func restoreLegacyBackupIfExplicitlyRequested(after error: Error) -> Bool {
        guard case WriterFlowDatabaseError.missingKey = error,
              ProcessInfo.processInfo.environment["WRITERFLOW_RESTORE_LEGACY_BACKUP"] == "1" else {
            return false
        }
        let directory = AzureModelsConfig.appSupportURL
        let encryptedURL = directory.appendingPathComponent(encryptedFileName)
        let plaintextURL = directory.appendingPathComponent(plaintextFileName)
        let backupURL = plaintextURL.deletingPathExtension()
            .appendingPathExtension("db.plaintext-backup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return false }

        do {
            let quarantined = directory.appendingPathComponent("writerflow.unreadable.enc.db")
            try? FileManager.default.removeItem(at: quarantined)
            if FileManager.default.fileExists(atPath: encryptedURL.path) {
                try FileManager.default.moveItem(at: encryptedURL, to: quarantined)
            }
            try FileManager.default.moveItem(at: backupURL, to: plaintextURL)
            DatabaseKeychain.delete(scope: AccountDatabaseScope.currentDatabaseKeyScope)
            Log.store.notice("Restoring the explicitly selected legacy database backup")
            return true
        } catch {
            Log.store.error("Legacy database recovery failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
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

    static func settingData(forKey key: String) -> Data? {
        try? shared.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM app_settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    @discardableResult
    static func setSettingData(_ data: Data, forKey key: String) -> Bool {
        do {
            try shared.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO app_settings (key, value)
                        VALUES (?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """,
                    arguments: [key, data]
                )
            }
            return true
        } catch {
            Log.store.error("Could not persist encrypted setting \(key, privacy: .public)")
            return false
        }
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
            let sqliteIntegrity = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard sqliteIntegrity?.caseInsensitiveCompare("ok") == .orderedSame else {
                throw WriterFlowDatabaseError.integrityCheckFailed(sqliteIntegrity ?? "no integrity result")
            }
            let foreignKeyFailures = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pragma_foreign_key_check"
            ) ?? 0
            guard foreignKeyFailures == 0 else {
                throw WriterFlowDatabaseError.integrityCheckFailed(
                    "\(foreignKeyFailures) foreign-key violation(s)"
                )
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
        let rollbackURL = encryptedURL.deletingLastPathComponent()
            .appendingPathComponent(rollbackFileName)

        try? fileManager.removeItem(at: migratingURL)
        try? fileManager.removeItem(at: rollbackURL)

        let source = try DatabaseQueue(path: plaintextURL.path)
        try migrator.migrate(source)
        let rollbackPassphrase = hexPassphrase(
            from: DatabaseKeychain.keyOrCreate(scope: rollbackKeyScope)
        )

        do {
            try source.write { db in
                try db.execute(
                    sql: """
                        ATTACH DATABASE ? AS rollback KEY ?;
                        SELECT sqlcipher_export('rollback');
                        ATTACH DATABASE ? AS encrypted KEY ?;
                        SELECT sqlcipher_export('encrypted');
                        """,
                    arguments: [
                        rollbackURL.path,
                        rollbackPassphrase,
                        migratingURL.path,
                        passphraseHex
                    ]
                )
            }
        } catch {
            try? source.close()
            try? fileManager.removeItem(at: migratingURL)
            try? fileManager.removeItem(at: rollbackURL)
            DatabaseKeychain.delete(scope: rollbackKeyScope)
            throw WriterFlowDatabaseError.migrationExportFailed(error.localizedDescription)
        }
        try source.close()

        let rollback = try openEncrypted(at: rollbackURL, passphraseHex: rollbackPassphrase)
        try verifyCipherIntegrity(rollback)
        try rollback.close()

        let encrypted = try openEncrypted(at: migratingURL, passphraseHex: passphraseHex)
        defer { try? encrypted.close() }

        try verifyCipherIntegrity(encrypted)
        try migrator.migrate(encrypted)

        if fileManager.fileExists(atPath: encryptedURL.path) {
            try fileManager.removeItem(at: encryptedURL)
        }
        try fileManager.moveItem(at: migratingURL, to: encryptedURL)
        try fileManager.removeItem(at: plaintextURL)

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: plaintextURL.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
    }

    private static func cleanupExpiredRollback(in directory: URL, fileManager: FileManager) {
        let rollbackURL = directory.appendingPathComponent(rollbackFileName)
        guard let attributes = try? fileManager.attributesOfItem(atPath: rollbackURL.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) > 7 * 24 * 60 * 60 else { return }
        do {
            try fileManager.removeItem(at: rollbackURL)
            DatabaseKeychain.delete(scope: rollbackKeyScope)
        } catch {
            Log.store.error("Could not remove expired encrypted migration rollback")
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

        migrator.registerMigration("v3_encrypted_settings") { db in
            try db.create(table: "app_settings", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("value", .blob).notNull()
            }
        }

        return migrator
    }
}

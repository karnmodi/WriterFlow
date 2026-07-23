import GRDB
import XCTest
@testable import WriterFlow

final class AccountDatabaseScopeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AccountDatabaseScope.resetForTesting()
    }

    override func tearDown() {
        if let scope = AccountDatabaseScope.boundIdentityHash {
            DatabaseKeychain.delete(scope: scope)
        }
        AccountDatabaseScope.resetForTesting()
        super.tearDown()
    }

    func testIdentityHashIsStableAndDistinct() {
        let hashA = AccountDatabaseScope.identityHash(
            issuer: "https://writerflow.ciamlogin.com/t/v2.0",
            subject: "user-a"
        )
        let hashB = AccountDatabaseScope.identityHash(
            issuer: "https://writerflow.ciamlogin.com/t/v2.0",
            subject: "user-b"
        )

        XCTAssertEqual(hashA.count, 64)
        XCTAssertEqual(hashB.count, 64)
        XCTAssertNotEqual(hashA, hashB)
        XCTAssertEqual(
            hashA,
            AccountDatabaseScope.identityHash(
                issuer: "https://writerflow.ciamlogin.com/t/v2.0",
                subject: "user-a"
            )
        )
    }

    func testBindIdentityIfUnboundPersistsHashOnce() {
        let issuer = "https://writerflow.ciamlogin.com/t/v2.0"
        let subject = "bind-once"

        let first = AccountDatabaseScope.bindIdentityIfUnbound(issuer: issuer, subject: subject)
        let second = AccountDatabaseScope.bindIdentityIfUnbound(issuer: issuer, subject: "different-subject")

        XCTAssertEqual(AccountDatabaseScope.boundIdentityHash, first)
        XCTAssertEqual(second, first, "an existing binding must not be overwritten silently")
        XCTAssertEqual(AccountDatabaseScope.currentDatabaseKeyScope, first)
    }

    func testRecordDeviceSessionIdentitySyncsOnLaterOpen() {
        AccountDatabaseScope.recordDeviceSessionIdentity(
            issuer: "https://writerflow.ciamlogin.com/t/v2.0",
            subject: "offline-reopen"
        )

        AccountDatabaseScope.resetForTesting()
        UserDefaults.standard.set(
            "https://writerflow.ciamlogin.com/t/v2.0",
            forKey: "com.karan.writerflow.deviceSession.entraIssuer"
        )
        UserDefaults.standard.set("offline-reopen", forKey: "com.karan.writerflow.deviceSession.entraSubject")

        AccountDatabaseScope.syncBindingFromDeviceSessionDefaults()

        XCTAssertNotNil(AccountDatabaseScope.boundIdentityHash)
        XCTAssertEqual(
            AccountDatabaseScope.boundIdentityHash,
            AccountDatabaseScope.identityHash(
                issuer: "https://writerflow.ciamlogin.com/t/v2.0",
                subject: "offline-reopen"
            )
        )
    }

    func testWriterFlowTokenBindsOnceAndRejectsDifferentIdentity() throws {
        func token(subject: String) throws -> String {
            let payload = try JSONSerialization.data(withJSONObject: [
                "iss": "https://apiwriterflow.aviusolutions.com",
                "sub": subject
            ])
            return "header.\(payload.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")).signature"
        }

        XCTAssertTrue(AccountDatabaseScope.recordWriterFlowAccessTokenIdentity(try token(subject: "user-a")))
        let bound = try XCTUnwrap(AccountDatabaseScope.boundIdentityHash)

        XCTAssertFalse(AccountDatabaseScope.recordWriterFlowAccessTokenIdentity(try token(subject: "user-b")))
        XCTAssertEqual(AccountDatabaseScope.boundIdentityHash, bound)
    }
}

final class DatabaseKeychainTests: XCTestCase {
    private let scopeA = "scope-a-\(UUID().uuidString)"
    private let scopeB = "scope-b-\(UUID().uuidString)"

    override func tearDown() {
        DatabaseKeychain.delete(scope: scopeA)
        DatabaseKeychain.delete(scope: scopeB)
        super.tearDown()
    }

    func testKeyOrCreateReusesExistingKeyForScope() {
        let first = DatabaseKeychain.keyOrCreate(scope: scopeA)
        let second = DatabaseKeychain.keyOrCreate(scope: scopeA)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32)
    }

    func testDifferentScopesGetDifferentKeys() {
        let keyA = DatabaseKeychain.keyOrCreate(scope: scopeA)
        let keyB = DatabaseKeychain.keyOrCreate(scope: scopeB)

        XCTAssertNotEqual(keyA, keyB)
    }

    func testBaseQueryNeverSetsAnAccessGroup() {
        XCTAssertNil(DatabaseKeychain.baseQuery(scope: scopeA)[kSecAttrAccessGroup as String])
    }

    func testRepairAccountKeyFromUnscopedOverwritesDivergedScopedKey() {
        let unscoped = DatabaseKeychain.generateKey()
        let wrongScoped = DatabaseKeychain.generateKey()
        XCTAssertTrue(DatabaseKeychain.write(unscoped, scope: nil))
        XCTAssertTrue(DatabaseKeychain.write(wrongScoped, scope: scopeA))
        XCTAssertNotEqual(DatabaseKeychain.read(scope: scopeA), unscoped)

        XCTAssertTrue(DatabaseKeychain.repairAccountKeyFromUnscoped(scope: scopeA))
        XCTAssertEqual(DatabaseKeychain.read(scope: scopeA), unscoped)

        DatabaseKeychain.delete(scope: nil)
    }
}

final class WriterFlowDatabaseTests: XCTestCase {
    private var tempRoot: URL!
    private var scope: String!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("writerflow-db-test-\(UUID().uuidString)", isDirectory: true)
        scope = "test-scope-\(UUID().uuidString)"
        DatabaseKeychain.delete(scope: scope)
    }

    override func tearDown() {
        DatabaseKeychain.delete(scope: scope)
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testFreshInstallCreatesEncryptedDatabase() throws {
        let queue = try WriterFlowDatabase.openForTesting(baseDirectory: tempRoot, scope: scope)
        defer { try? queue.close() }

        try queue.write { db in
            try db.execute(sql: "INSERT INTO memory_notes (id, kind, text, enabled, updatedAt) VALUES (?, ?, ?, ?, ?)", arguments: ["1", "rule", "note", true, Date()])
        }

        let encryptedURL = tempRoot.appendingPathComponent(WriterFlowDatabase.encryptedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(WriterFlowDatabase.plaintextFileName).path))

        try queue.read { db in
            let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version")
            XCTAssertFalse((cipherVersion ?? "").isEmpty)
        }
    }

    func testPlaintextDatabaseMigratesToEncryptedFile() throws {
        let plainRoot = tempRoot.appendingPathComponent("plain-seed", isDirectory: true)
        try FileManager.default.createDirectory(at: plainRoot, withIntermediateDirectories: true)
        let plainURL = plainRoot.appendingPathComponent(WriterFlowDatabase.plaintextFileName)
        try WriterFlowDatabase.seedPlaintextDatabase(at: plainURL)

        let queue = try WriterFlowDatabase.openForTesting(
            baseDirectory: tempRoot,
            scope: scope,
            seedPlaintext: plainURL
        )
        defer { try? queue.close() }

        let note = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM memory_notes WHERE id = ?", arguments: ["legacy-1"])
        }
        XCTAssertEqual(note, "migrated note")

        let encryptedURL = tempRoot.appendingPathComponent(WriterFlowDatabase.encryptedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent(WriterFlowDatabase.plaintextFileName).path
            )
        )
        let rollbackURL = tempRoot.appendingPathComponent(WriterFlowDatabase.rollbackFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackURL.path))
        let rollbackBytes = try Data(contentsOf: rollbackURL)
        XCTAssertNil(
            rollbackBytes.range(of: Data("migrated note".utf8)),
            "rollback artifact must remain encrypted"
        )
    }

    func testWrongPassphraseFailsClosed() throws {
        let queue = try WriterFlowDatabase.openForTesting(baseDirectory: tempRoot, scope: scope)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO memory_notes (id, kind, text, enabled, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["1", "rule", "secret", true, Date()]
            )
        }
        try queue.close()

        let encryptedURL = tempRoot.appendingPathComponent(WriterFlowDatabase.encryptedFileName)
        let wrongKey = DatabaseKeychain.generateKey()
        let wrongPassphrase = WriterFlowDatabase.hexPassphrase(from: wrongKey)

        XCTAssertThrowsError(
            try DatabaseQueue(
                path: encryptedURL.path,
                configuration: WriterFlowDatabase.makeConfiguration(passphraseHex: wrongPassphrase)
            )
        )
    }

    func testHexPassphraseIs64Characters() {
        let key = DatabaseKeychain.generateKey()
        let hex = WriterFlowDatabase.hexPassphrase(from: key)
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit })
    }

    func testLegacyDatabaseMovesIntoAccountScopeWithMainFileAsCommitMarker() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let files = [
            WriterFlowDatabase.encryptedFileName,
            "\(WriterFlowDatabase.encryptedFileName)-wal",
            "\(WriterFlowDatabase.encryptedFileName)-shm"
        ]
        for file in files {
            try Data(file.utf8).write(to: tempRoot.appendingPathComponent(file))
        }

        let directory = try WriterFlowDatabase.accountStorageDirectory(
            appSupport: tempRoot,
            scope: scope,
            fileManager: .default
        )

        XCTAssertEqual(directory, tempRoot.appendingPathComponent("accounts/\(scope!)"))
        for file in files {
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(file).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path))
        }
    }

    func testInterruptedAccountMoveResumesBeforeMainCommitMarker() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let scoped = tempRoot.appendingPathComponent("accounts/\(scope!)", isDirectory: true)
        try FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)

        let main = WriterFlowDatabase.encryptedFileName
        let sidecar = "\(main)-wal"
        try Data("main".utf8).write(to: tempRoot.appendingPathComponent(main))
        try Data("wal".utf8).write(to: scoped.appendingPathComponent(sidecar))

        let directory = try WriterFlowDatabase.accountStorageDirectory(
            appSupport: tempRoot,
            scope: scope,
            fileManager: .default
        )

        XCTAssertEqual(directory, scoped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(main).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scoped.appendingPathComponent(main).path))
        XCTAssertEqual(try Data(contentsOf: scoped.appendingPathComponent(sidecar)), Data("wal".utf8))
    }

    func testAccountScopeConflictFailsClosed() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(
            to: tempRoot.appendingPathComponent(WriterFlowDatabase.encryptedFileName)
        )
        let scoped = tempRoot.appendingPathComponent("accounts/\(scope!)", isDirectory: true)
        try FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)
        try Data("scoped".utf8).write(
            to: scoped.appendingPathComponent(WriterFlowDatabase.encryptedFileName)
        )

        XCTAssertThrowsError(
            try WriterFlowDatabase.accountStorageDirectory(
                appSupport: tempRoot,
                scope: scope,
                fileManager: .default
            )
        ) { error in
            guard case WriterFlowDatabaseError.accountStorageConflict = error else {
                return XCTFail("Expected accountStorageConflict, got \(error)")
            }
        }
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}

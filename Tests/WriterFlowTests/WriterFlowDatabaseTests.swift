import GRDB
import XCTest
@testable import WriterFlow

final class AccountDatabaseScopeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AccountDatabaseScope.resetForTesting()
    }

    override func tearDown() {
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
}

final class DatabaseKeychainTests: XCTestCase {
    private let scopeA = "scope-a-\(UUID().uuidString)"
    private let scopeB = "scope-b-\(UUID().uuidString)"

    override func tearDown() {
        DatabaseKeychain.delete(scope: scopeA)
        DatabaseKeychain.delete(scope: scopeB)
        DatabaseKeychain.delete(scope: nil)
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
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}

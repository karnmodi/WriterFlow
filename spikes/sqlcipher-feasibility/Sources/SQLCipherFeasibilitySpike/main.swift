import Foundation
import GRDB

setbuf(stdout, nil) // unbuffered — this is a short-lived diagnostic CLI, not a hot loop

// Stage 5.3 SQLCipher feasibility spike. Proves, in isolation:
//   1. SPM + vendored GRDB(SQLCipher) actually builds on macOS.
//   2. A database opened with a random 256-bit key is genuinely SQLCipher-encrypted
//      (PRAGMA cipher_version confirms real linkage, not a silent plaintext fallback).
//   3. Write, close, reopen with the SAME key round-trips real data.
//   4. Reopening with the WRONG key fails closed rather than silently returning an
//      empty/corrupt database — the exact failure mode CLAUDE.md's "no silent in-memory
//      fallback" rule and this stage's Accept criteria care about.
// Never derives the key from anything other than system randomness, per this stage's
// "Do not derive the DB key from password, OAuth token, refresh token, email, or
// network state" rule.

func randomKey() -> Data {
    var bytes = [UInt8](repeating: 0, count: 32) // 256 bits
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(result == errSecSuccess, "SecRandomCopyBytes failed")
    return Data(bytes)
}

func makeConfiguration(key: Data) -> Configuration {
    var config = Configuration()
    config.prepareDatabase { db in
        try db.usePassphrase(key)
    }
    return config
}

let dbPath = FileManager.default.temporaryDirectory
    .appendingPathComponent("sqlcipher-spike-\(UUID().uuidString).sqlite").path
print("Spike database: \(dbPath)")

let key = randomKey()
let wrongKey = randomKey()

// 1 & 2: open with a real key, confirm SQLCipher is actually linked.
do {
    let dbQueue = try DatabaseQueue(path: dbPath, configuration: makeConfiguration(key: key))
    try dbQueue.write { db in
        guard let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version") else {
            fatalError("FAIL: PRAGMA cipher_version returned nil — GRDB is not linked against SQLCipher, it's using plain SQLite. This would silently produce an unencrypted database.")
        }
        print("SQLCipher version: \(cipherVersion)")
        try db.create(table: "note") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("body", .text).notNull()
        }
        try db.execute(sql: "INSERT INTO note (body) VALUES (?)", arguments: ["encrypted round-trip test"])
    }
    print("PASS: created encrypted DB, wrote a row.")
}

// 3: reopen with the SAME key, confirm the row survives.
do {
    let dbQueue = try DatabaseQueue(path: dbPath, configuration: makeConfiguration(key: key))
    let body = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT body FROM note LIMIT 1")
    }
    guard body == "encrypted round-trip test" else {
        fatalError("FAIL: reopening with the correct key did not return the written row (got \(body ?? "nil")).")
    }
    print("PASS: reopened with the correct key, row round-tripped.")
}

// 4: reopen with the WRONG key — must fail closed, never silently return empty/garbage data.
// GRDB validates the key immediately on open (an internal schema-priming query trips over
// the undecryptable page), so the failure can surface from DatabaseQueue's initializer
// itself, not just from a later read — wrap the whole attempt, not just the read.
do {
    let dbQueue = try DatabaseQueue(path: dbPath, configuration: makeConfiguration(key: wrongKey))
    _ = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT body FROM note LIMIT 1")
    }
    fatalError("FAIL: reading with the WRONG key succeeded — encryption is not actually protecting this file.")
} catch {
    print("PASS: reopening with the wrong key failed closed, as required: \(error)")
}

try? FileManager.default.removeItem(atPath: dbPath)
print("\nAll SQLCipher feasibility checks passed.")

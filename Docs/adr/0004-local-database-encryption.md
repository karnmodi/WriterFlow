# ADR-0004: Local database moves to GRDB + SQLCipher, key in Keychain

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

The current v1 `writerflow.db` (GRDB/SQLite) is plaintext, as is the voice profile
and recent custom instructions stored in `UserDefaults` (confirmed by inspection —
see `Docs/v2-data-inventory.md`). `WriterFlowDatabase.shared` also silently falls
back to an in-memory database on open/migration failure
(`Sources/WriterFlow/Store/WriterFlowDatabase.swift:17-21`), which becomes a
data-loss illusion once encryption is introduced.

## Decision

Keep GRDB as the persistence API but run it on SQLCipher. Generate a random 256-bit
local database key with Security-framework randomness, store it as a dedicated
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain item separate from the
WriterFlow device-token item (ADR-0011/0012). Never derive the key from password,
OAuth token, email, or network state. Remove the silent in-memory fallback for production data. Move
voice profile and recent custom instructions out of plaintext `UserDefaults` into
the encrypted database.

## Consequences

- A missing/wrong Keychain key cannot be recovered by any identity re-auth; the UI
  must present retry/unlock, a matching-key export restore if implemented, or an
  explicit reset — never a silently regenerated key over an "empty" database
  presented as recovered history.
- WriterFlow must own and pin the GRDB SQLCipher package fork/manifest, assign
  upstream/SQLCipher security-update ownership, and prove SQLCipher is the only
  linked SQLite implementation for every advertised Release architecture before
  this migration is written (Stage 5.3 feasibility gate).
- If the SPM+SQLCipher spike fails, the approved fallback is versioned CryptoKit
  AES-GCM field encryption with deliberately designed blind indexes — a distinct
  ADR is required before implementing that path, and it does not provide
  whole-file protection or general FTS/search.

## Revisit when

The Stage 5.3 SPM/GRDB/SQLCipher packaging spike fails on a required Release
architecture, triggering the CryptoKit fallback ADR.

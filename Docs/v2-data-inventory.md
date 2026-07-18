# V2 data inventory — v1 baseline

**Status:** Stage 5.0 deliverable
**Date:** 2026-07-17
**Method:** Direct inspection of the shipped v1.0.0 (`7255390`) source, not inferred
from specs. File/line references point at the current `main` working tree.

This inventory exists so Stage 5.3's local-encryption migration and Stage 5.0's
retention decisions cover every real location, not an assumed one. Every row must be
re-verified against the actual migration code before it is trusted as complete.

## 1. GRDB / SQLite — `~/Library/Application Support/WriterFlow/writerflow.db`

Source: `Sources/WriterFlow/Store/WriterFlowDatabase.swift`. Plaintext today.
**Hazard:** `WriterFlowDatabase.shared` silently falls back to an in-memory
`DatabaseQueue` if the on-disk open/migration fails (lines 17–21) — must be removed
before SQLCipher migration lands (ADR-0004).

| Table | Columns | Classification |
|---|---|---|
| `conversions` | `id, timestamp, appBundleID, site, action, input, output, accepted, model, tokensIn, tokensOut, latencyMs` | **User content** — `input`/`output` hold raw field text and AI output. Highest-sensitivity table. |
| `memory_notes` | `id, kind, text, enabled, updatedAt` | **User content** — free-text facts/snippets the user saved. |
| `app_rules` | `bundleOrSite, tone, signature, customInstruction, excluded, clipboardFallback` | **User content** — `customInstruction`/`signature` are free text; the rest is low-sensitivity config. |

Account-scope target (Stage 5.3): all three tables move under
`accounts/<account-hash>/writerflow.db`; none remain in a global store.

## 2. UserDefaults (`UserDefaults.standard`, domain `com.karan.writerflow`)

Source: `Sources/WriterFlow/Store/SettingsStore.swift`.

| Key | Type | Classification |
|---|---|---|
| `iconMode` | enum rawValue | Config, not user content |
| `isPaused` | bool | Config |
| `launchAtLogin` | bool | Config |
| `historyRetention` | enum rawValue | Config |
| `hotkeyCombo` | Data | Config |
| `forceClipboardFallback` | bool | Config |
| `recentCustomInstructions` | `[String]` | **User content** — plaintext free-text instructions the user typed. Must move to the encrypted DB. |
| `voiceProfile` | `Data` (encoded `VoiceProfile`) | **User content** — plaintext serialized voice/style profile, likely containing writing samples. Must move to the encrypted DB. |

Source: `Sources/WriterFlow/Store/AppRuleStore.swift` also writes one boolean
"seeded defaults" flag to `UserDefaults.standard` — content-free, can stay global.

## 3. Keychain

Source: `Sources/WriterFlow/Store/KeychainStore.swift`.

| Item | Service / Account | Accessibility | Classification |
|---|---|---|---|
| BYO Azure API key | `com.karan.writerflow` / `azure-openai-api-key` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | **Secret** — user's own key, v1 production path. Retained only as the time-limited v2 alpha rollback (ADR-0009 context; phase-5 Stage 5.6). |

V2 adds two more Keychain items that must stay logically separate from this one and
from each other: the WriterFlow device token (access + rotating refresh) in the app's
own item, no shared access group (ADR-0011/0012), and the local SQLCipher database key
(`WhenUnlockedThisDeviceOnly`, ADR-0004). No Entra/MSAL token cache exists on the Mac.

## 4. Application Support JSON files

`~/Library/Application Support/WriterFlow/`, source:
`Sources/WriterFlow/Store/AzureModelsConfig.swift`,
`Sources/WriterFlow/Engine/CompatibilityMap.swift`.

| File | Contents | Classification |
|---|---|---|
| `models.json` | User's own Azure endpoint URL + deployment names (no key) | Config — not secret, but user-specific. Removed from the v2 production client path (ADR-0006); retained only under the migration-only advanced section during alpha. |
| `compatibility.json` | Per-bundle AX read/write success/fail counters only | **Content-free.** Explicitly safe to keep as a global, non-account-scoped file (`V2-ARCHITECTURE.md` §4.2). |
| `secrets.env` (DEBUG only) | Plaintext `API_KEY_*` / `TARGET_URI` values, `0o600` | **Secret, local-dev only.** `KeychainStore.swift` guards this behind `#if DEBUG`; must never ship in a release artifact — already covered by v1's `make verify-release` secret scan. |

## 5. Diagnostics export (user-triggered)

Source: `Sources/WriterFlow/Store/DiagnosticsExporter.swift`. Combines system info,
`compatibility.json` (content-free counters), and macOS crash reports from
`~/Library/Logs/DiagnosticReports/`. Does **not** currently include `conversions`,
`memory_notes`, or `app_rules` content — confirmed content-safe by inspection. This
property must be preserved (and re-verified) as diagnostics evolve in v2.

## 6. Transient / in-memory only

- Focused-field snapshot and extracted conversation context
  (`Sources/WriterFlow/Engine/FieldSnapshot.swift`,
  `Sources/WriterFlow/Engine/ContextExtractor.swift`) — held in memory only for the
  duration of one explicit action, then either discarded or written into
  `conversions` as `input`/`output`.
- System clipboard (`Sources/WriterFlow/Engine/ClipboardWriter.swift`,
  `Sources/WriterFlow/Engine/TextInserter.swift`) — used for the clipboard-fallback
  replace path. Not WriterFlow-persisted, but readable by any other app/clipboard
  manager on the Mac until overwritten; this is an existing v1 risk (see README's
  password-manager-exclusion note), not a new v2 surface.

## 7. Not present in v1 (net-new in v2 — see `V2-ARCHITECTURE.md` §8)

No user/organization/membership/entitlement/billing/usage data exists anywhere in
v1. All of `users`, `auth_identities`, `organizations`, `organization_memberships`,
`devices`, `privacy_preferences`, `inference_requests`, `quota_reservations`,
`usage_ledger`, `usage_balances`, `pricing_versions`, `entitlement_grants`,
`entitlement_projection`, `stripe_events`, `outbox_events`, `user_data_keys`,
`personalization_profiles`, and `personalization_rules` are net-new PostgreSQL
tables introduced by Phase 5/7. Retention/deletion behavior for each must be fixed
before its migration is written — tracked as the next Stage 5.0 sub-task.

## Open follow-up (remaining Stage 5.0 work)

- [x] Per-table cloud retention/deletion policy — `Docs/v2-data-retention-policy.md`,
  covering every table Stage 5.1 actually migrates (ties into `Docs/v2-threat-model.md`
  and `V2-ARCHITECTURE.md` §7.3). Phase 7 tables (Stripe, personalization sync) are
  explicitly out of scope until their migrations are written.
- [ ] Confirm crash reports never capture in-memory field/context content on a real
  crash (requires a forced-crash test, not just a code read).

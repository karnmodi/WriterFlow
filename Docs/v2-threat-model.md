# V2 threat model — Phase 5 cloud foundation

**Status:** Stage 5.0 deliverable
**Date:** 2026-07-17
**Scope:** Identity, transport, and local-encryption trust boundary introduced by
Phase 5. Contextual-classifier injection risk is elaborated further in Phase 6
(`V2-ARCHITECTURE.md` §12.1); billing/webhook risk is elaborated further in Phase 7.

Each entry: threat → why it matters here → mitigation (with owning ADR/architecture
section) → residual risk that must stay visible, not hidden by the mitigation.

## 1. Token theft (stolen WriterFlow access or refresh token)

A copied bearer token or device-ID header is not distinguishable from the real
client by the edge alone (`V2-ARCHITECTURE.md` §5.3). The Mac holds a WriterFlow
device token (ADR-0012), not an Entra token or MSAL cache.

- **Mitigation:** short-lived WriterFlow access tokens; refresh tokens stored hashed,
  rotated on every use with reuse detection (a replayed refresh revokes the family);
  APIM `validate-jwt` (WriterFlow JWKS) + application-layer re-check on every request;
  device revoke and account disable. Tokens live in the app's own Keychain item, not a
  WriterFlow-invented store.
- **Residual risk:** until a supported token-binding standard (DPoP/mTLS) is
  adopted, a stolen live *access* token is valid until it expires (short) or the device
  is revoked; a stolen *refresh* token is caught only on next use by rotation/reuse
  detection. Detection relies on anomaly alerting (Stage 5.6), not prevention.

## 2. Malicious or tampered client

A user controls their own Mac and can patch the binary or replay captured traffic
from a modified client. The app is ad-hoc signed with no Developer ID (ADR-0010).

- **Mitigation:** no security-by-obscurity claims; all authorization is
  server-side (ADR-0005, ADR-0011). Code signing is not relied on as an anti-tamper or
  authorization control at all — ad-hoc signing provides none, and the design never
  assumed it did.
- **Residual risk:** a technically sophisticated user can still call the API with
  a valid token from a non-WriterFlow client within their own entitlement — this is
  accepted as equivalent to normal API abuse risk, bounded by quota/rate limits.
  Unsigned distribution slightly lowers the bar for third-party tampered redistribution;
  this is accepted as out of scope of the server authorization boundary.

## 2a. Device-pairing abuse (code phishing, polling abuse, issuer compromise)

The pairing flow (ADR-0011) adds `device_code`/`user_code` and a WriterFlow token
issuer (ADR-0012) — new surface not present when auth was in-app MSAL.

- **Mitigation:** `device_code` is single-use, short-lived, and PKCE-bound so a code
  observed in transit cannot be redeemed without the app's `code_verifier`; `user_code`
  is high-entropy enough to resist guessing and is rate-limited at APIM; the browser
  shows requesting-device metadata before approval so a user can spot a phished pairing;
  `/v2/device/*` are the only bearer-exempt routes and carry strict method/body/rate
  policy; the token-signing key lives in Key Vault with rotation and a published JWKS.
- **Residual risk:** a user socially engineered into approving an attacker's pending
  pairing grants that device a session — mitigated by clear device-metadata display and
  device revoke, not fully prevented. Signing-key compromise is a high-impact event
  handled by rotation runbooks (Stage 8.1), not by the flow itself.

## 3. Replay of a completed or in-flight operation

Same idempotency key resubmitted, or a captured request replayed later.

- **Mitigation:** unique `(user_id, idempotency_key)` constraint; reusing a
  completed key returns final status without a new provider call; the app never
  auto-generates a new operation ID after output begins
  (`V2-ARCHITECTURE.md` §6.4).
- **Residual risk:** none expected if the constraint and status-lookup path are
  implemented as specified — this is a correctness property to test explicitly in
  Stage 5.4/5.5, not just assumed from the schema.

## 4. Idempotency / quota race under concurrency

Two concurrent requests with the same or different keys attempting to exceed the
worst-case reservation.

- **Mitigation:** request row + quota reservation created in one DB transaction
  before provider work starts (Stage 5.4 minimum accounting prerequisite);
  simulated concurrent-request test required before Stage 5.5 exit.
- **Residual risk:** reservation is worst-case, not exact-cost; a burst of
  denied-but-attempted requests is possible under heavy concurrency and must be
  rate-limited at APIM as a separate, non-authoritative control.

## 5. Cross-tenant / cross-organization access

A request for one organization's data resolves against another's.

- **Mitigation:** RLS with `FORCE ROW LEVEL SECURITY` on every tenant-owned table;
  runtime role has no `BYPASSRLS`; application code binds all work to the
  server-resolved organization, never a client-supplied org ID (ADR-0003).
- **Residual risk:** pooled-connection tenant-context bleed is a known PostgreSQL
  RLS pitfall — explicitly called out as a required negative test
  (`V2-ARCHITECTURE.md` §17) before this mitigation can be trusted in production.

## 6. Prompt injection via field/context/conversation content

Hostile instructions hidden in email/chat/context text, personalization fields, or
even model output attempting to change behavior.

- **Mitigation:** trust-class separation in prompt compilation — reviewed policy,
  server-resolved constraints, explicit user instruction, personalization, and
  quoted untrusted content are distinct message/content parts; classifier/output-
  mode/route results are validated against closed enums, never free-form
  (`V2-ARCHITECTURE.md` §12.1). No tool calls, no client-selected URL/model/
  template.
- **Residual risk:** full mitigation requires the Phase 6 structured classifier and
  typed `PromptPlan`; Phase 5's server prompt port is behavior-equivalent to v1 and
  inherits v1's injection posture until Stage 6.4 lands. Injection fixtures are a
  named Stage 5.0 test-fixture deliverable regardless.

## 7. Oversized context / request

A client sends an abnormally large field, conversation, or custom-instruction
payload to exhaust cost or storage.

- **Mitigation:** server-independent caps on every string field, total request
  bytes, context nodes/chars, output tokens, operation duration, and concurrent
  operations, enforced before provider access (Stage 5.0 contracts,
  `TARGET_TOO_LARGE` error code).
- **Residual risk:** initial caps reuse v1's baseline until measured; caps may need
  retuning once real traffic patterns are observed.

## 8. SSE disconnect / retry ambiguity

Network drop mid-stream, before or after the model has produced output.

- **Mitigation:** canonical event ordering with exactly one `decision` and one
  `usage.summary`; Replace/Copy disabled until `completed`; disconnect before first
  delta allows provider retry within the route's attempt budget, disconnect after
  first delta does not silently retry; failed/cancelled requests commit zero
  customer billable units while retaining internal cost/abuse accounting
  (`V2-ARCHITECTURE.md` §6.4).
- **Residual risk:** the user experiences "result could not be recovered" for a
  stream that broke after delivering partial text — by design (no server-side
  replay buffer), but must be tested for a good failure UX, not just correctness.

## 9. Provider failover producing duplicate billable output

A retry/failover path accidentally calls the model twice and bills twice, or
returns two different completions to the client.

- **Mitigation:** retry/failover only permitted before the first emitted delta;
  one immutable ledger record per provider attempt/stage; append-only ledger with
  corrections as reversing entries, not mutation (`V2-ARCHITECTURE.md` §10.2, §8.3).
- **Residual risk:** requires the Stage 5.5 hardened accounting path; the Stage 5.4
  minimum slice only proves single-attempt metering for one action (Fix Grammar).

## 10. Usage double-counting / billing drift

Ledger and actual provider cost diverge, or a meter event is emitted twice.

- **Mitigation:** append-only `usage_ledger` keyed by request/stage/attempt;
  `usage_balances` updated transactionally; scheduled reconciliation job against
  provider invoices; Stripe meter events (Phase 7) generated from committed ledger
  rows with the ledger UUID as the idempotent meter-event identifier, never from
  the inference handler directly.
- **Residual risk:** out of Phase 5 scope for Stripe specifically (ADR-0009); the
  ledger-correctness property must hold before Phase 7 can trust it.

## 11. Key Vault / database key loss

Loss of the KEK (cloud envelope encryption) or the local SQLCipher DB key.

- **Mitigation:** Key Vault soft-delete + purge protection + rotation alerts for
  the cloud KEK; local DB key isolated in its own Keychain item, never derivable
  from auth state (ADR-0004). Recovery runbooks required before Stage 8.1 exit.
- **Residual risk:** local DB key loss is **not recoverable** by design — a new key
  cannot decrypt old ciphertext. This must be disclosed to the user plainly in the
  recovery UI, not hidden behind a generic error.

## 12. Log / telemetry content leakage

Field text, prompts, or output accidentally reach logs, traces, or the usage DB.

- **Mitigation:** logger allowlist rejecting content keys; APIM SSE body
  logging/caching disabled; canary-content tests at APIM, API, monitor, and DB
  layers (named Stage 5.0 test fixture and Stage 5.6 live-matrix item).
- **Residual risk:** this is the single most likely "quiet" regression as new
  routes are added — canary tests must run in CI on every PR that touches the
  logging path, not just once at launch.

## 13. V1 → V2 local migration interruption

Forced quit, disk-full, wrong Keychain key, or corrupt source during the one-time
SQLCipher migration.

- **Mitigation:** backup + verify + atomic swap + rollback archive (itself
  encrypted, under a distinct Keychain key, deleted at a hard deadline); cancel-
  before-swap and recovery-after-interruption at every checkpoint
  (`V2-ARCHITECTURE.md` §7.1, phase-5 Stage 5.3).
- **Residual risk:** this is the highest user-visible-harm risk in Phase 5 (it can
  look like WriterFlow deleted someone's history) — forced-interruption tests at
  every checkpoint are a hard Stage 5.3 acceptance gate, not optional coverage.

## 14. Native-client identity limitation (explicit acknowledgment)

No embedded secret, obfuscated string, or custom signing scheme proves the calling
process is the real WriterFlow.app. This is a structural property of a distributed
desktop client (RFC 8252's rationale still applies even though auth is now
browser-mediated and the app holds a per-device WriterFlow token, ADR-0011/0012), not
a bug to "fix" with more obfuscation.

- **Mitigation:** none pretends to solve this; the design goal is a public,
  authenticated edge with private origin/model access and server-side authorization
  at every layer, not an unachievable "private API from a public client."
- **Residual risk:** accepted permanently; revisited only if a supported token-
  binding standard becomes viable (see threat 1).

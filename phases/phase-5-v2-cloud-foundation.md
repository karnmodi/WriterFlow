# Phase 5 — V2 cloud foundation, identity, and encrypted transport

**Goal:** Preserve WriterFlow's v1 native experience while replacing the BYO Azure trust
boundary with real-user authentication, encrypted account-scoped local data, and one
authenticated WriterFlow streaming API backed by private Azure services.

**Inputs:** [`PRD-V2.md`](../PRD-V2.md),
[`V2-ARCHITECTURE.md`](../V2-ARCHITECTURE.md), and
[`V2-ROADMAP.md`](../V2-ROADMAP.md).

This phase intentionally keeps the existing action menu. Auto selection and removal of
the options flow are Phase 6 work, after the transport is proven independently.

## Phase-wide non-negotiables

- Passive typing remains local and never refreshes auth or starts inference.
- Clicking the icon, choosing an action, submitting Custom/Prompt Builder, or pressing
  the explicit hotkey is still the network authorization boundary.
- No WriterFlow-owned Azure key, Stripe secret, database credential, client secret,
  private endpoint, or deployment name ships in the Mac app.
- The app-facing edge is public and authenticated; Container Apps origin, PostgreSQL,
  Key Vault, and Azure OpenAI have no public ingress in staging/production.
- Raw field/context/prompt/output content is absent from server/gateway logs and the
  cloud database by default.
- Existing v1 local data and BYO credentials are not deleted during migration.
- No operation invokes both BYO and WriterFlow cloud inference.
- Every provider call, including classifier/style analysis, gets a server-side usage
  stage record.
- A failed encrypted-database open never falls back to an apparently empty in-memory
  store.

## Stage 5.0 — Decisions, threat model, and contracts

### Product and security decisions

- [x] Add short ADRs that freeze the Phase 5 decisions — `Docs/adr/0001`–`0012`:
  - managed customer identity = Microsoft Entra External ID (web-side confidential
    client per ADR-0011 amendment);
  - ~~native auth = browser Authorization Code + PKCE, no client secret~~ **superseded by
    ADR-0011**: auth/membership in the browser, Mac pairs via device-authorization flow;
  - cloud DB = Azure Database for PostgreSQL Flexible Server;
  - local DB = GRDB + SQLCipher, key in Keychain;
  - app edge = API Management, private origin = Container Apps;
  - provider auth = managed identity/RBAC and private endpoint;
  - inference content = ephemeral by default;
  - ~~stable Developer ID app identity required before external alpha~~ **superseded by
    ADR-0010**: no Apple Developer account; v2 keeps v1 ad-hoc distribution;
  - Stripe/paid enforcement = not part of Phase 5;
  - ADR-0011 = browser-mediated auth + device pairing;
  - ADR-0012 = WriterFlow backend is the device-token issuer.
- [x] Inventory v1 data by location and classification — `Docs/v2-data-inventory.md`,
  built from direct source inspection (`writerflow.db` tables, `models.json`,
  `compatibility.json`, UserDefaults keys, the Keychain BYO-key item, DEBUG-only
  `secrets.env`, diagnostics export, and in-memory field/context/output/clipboard).
- [x] Define retention and deletion behavior for every new cloud table before its
  migration is written. — `Docs/v2-data-retention-policy.md`, covering every table
  Stage 5.1's PostgreSQL baseline actually migrates (retention default, deletion
  trigger, deletion mechanism per table, plus the account-deletion sequencing across
  them). Phase 7 tables (Stripe, personalization sync) get their own policy when their
  migrations are written.
- [x] Threat-model at minimum: token theft, malicious/tampered client, replay,
  idempotency race, quota race, cross-tenant access, prompt injection, oversized
  context, SSE disconnect/retry, provider failover, usage double-count, Key Vault/DB key
  loss, log leakage, and v1 migration interruption — `Docs/v2-threat-model.md`.
- [x] Explicitly document the native-public-client limitation: no embedded shared secret
  proves app identity; do not invent custom crypto as a workaround. —
  `Docs/v2-threat-model.md` §14 and ADR-0002.

### Contracts

- [x] Define versioned JSON schemas/OpenAPI for:
  - device pairing (`/v2/device/authorize`, `/v2/device/approve`, `/v2/device/token`,
    `/v2/token/refresh`) and the `AccountSnapshot` returned by approve/`/v2/me`
    (this replaces the former Mac-authenticated `/v2/bootstrap`; ADR-0011/0012);
  - device list/revoke;
  - a discriminated inference envelope with `mode = explicit|auto`, current
    `WritingAction`, Custom instruction, Prompt Builder analyze/finalize/answers,
    selection-vs-field scope, and output-mode hint fields required for v1 parity;
  - typed inference SSE events and canonical ordering: accepted, decision (including
    output mode), optional Prompt Builder questions, output deltas, usage summary,
    completed, or terminal sanitized error;
  - style-analysis request/result;
  - safe error codes;
  - logical route and allowance labels exposed to the app.

  See `Docs/contracts/openapi.yaml` (REST) and `Docs/contracts/inference-stream.md` +
  `Docs/contracts/schemas/*.schema.json` (SSE). Version `2.0.0-alpha.1`; treat as
  draft until Stage 5.0 architecture review signs off.
- [x] Require `Authorization`, `Idempotency-Key`, client version, and device ID on
  inference/style calls — encoded as required parameters in `openapi.yaml`.
- [x] Cap every text field, total request bytes, context nodes/chars, output tokens,
  operation duration, and concurrent operations. Keep current v1 context caps as the
  starting baseline until measured. — `maxLength`/`maxItems` bounds are in
  `inference-request.schema.json`; values reuse v1's existing caps as a first pass
  and must be re-validated against real Stage 5.1 traffic, not treated as final.
- [x] Decide canonical operation states and transitions:
  `reserved → running → streaming → completed|failed|cancelled` — documented in
  `Docs/contracts/inference-stream.md`.
- [x] Define retry rules: provider retry/failover only before first delta; preview Retry is
  a new explicit operation; the same idempotency key never triggers another model call.
  — `Docs/contracts/inference-stream.md` "Retry and idempotency rules".
- [x] Define broken-stream behavior: partial output cannot Replace/Copy, same-key status
  lookup makes no provider call, failed/cancelled delivery debits zero customer units
  while retaining internal provider-cost/abuse accounting, and explicit Retry links a
  new operation through `retryOf`. — same section.
- [x] Define strict discriminated-union validation: reject unknown modes/actions/phases,
  require Custom/Prompt Builder fields conditionally, and validate decision/output mode
  before any preview text becomes replaceable. — encoded in
  `inference-request.schema.json` (`additionalProperties: false`, conditional
  required fields) and `sse-events.schema.json` (`oneOf` discriminated union).
- [x] Define log fields allowed for inference: request ID, user/org/device IDs in
  pseudonymous form, logical route, prompt version, char/token counts, latency, status,
  and safe error code. Text is forbidden. — `Docs/contracts/inference-stream.md`
  "Allowed log fields".

- [x] Create synthetic fixtures for each current `WritingAction`, empty Reply, Custom
  insert mode, Prompt Builder analyze/finalize, style analysis, cancellation, timeout,
  429, 5xx, and disconnected SSE. — `Docs/contracts/fixtures/requests/*.json` (one
  envelope per action + empty Reply + Custom insert mode + Prompt Builder
  analyze/finalize + style analysis, all schema-validated) and
  `Docs/contracts/fixtures/events/*.json` (happy-path, cancellation, timeout, 429,
  5xx, disconnected-mid-stream event sequences, all schema-validated against
  `sse-events.schema.json`). Data-only; the Stage 5.1 TypeScript harness wires them to
  a runner (`Docs/contracts/fixtures/README.md`).
- [x] Create redaction tests with canary secrets in draft/context to prove they never
  appear in logs, traces, errors, or usage rows. — fixture data in
  `Docs/contracts/fixtures/redaction/canary-secrets.json`; the assertion runs once the
  Stage 5.1 logging path exists.
- [x] Create prompt-injection fixtures in conversation, draft, Custom instruction,
  personalization, Prompt Builder answers, and model output. Prove untrusted text cannot
  change authorization, retention, tools, deployment, route allowlist, or output mode
  outside the validated task contract. — fixture data in
  `Docs/contracts/fixtures/prompt-injection/injection-vectors.json`, six vectors with a
  stated `expectedSafeOutcome` each; assertion runs once Stage 5.1's server exists
  (Phase 5 inherits v1's injection posture per `Docs/v2-threat-model.md` #6 — full
  mitigation is Stage 6.4).

**Accept:** architecture review signs off on ADRs, threat model, data inventory, API
schema, retry/idempotency state machine, and privacy/logging contract before cloud code
or database migrations become release dependencies.

**Suggested commit:** `phase5.0: freeze v2 security boundary and API contracts`

## Stage 5.1 — Backend, database, infrastructure, and CI skeleton

### Repository structure

- [ ] Add `services/api`, `services/worker`, and `services/shared` as one TypeScript
  workspace with strict type checking, linting, unit tests, and locked dependencies.
- [ ] Use Fastify for HTTP/SSE and a migration/query layer that preserves explicit SQL,
  transactions, constraints, and migration review.
- [ ] Add `infra/bicep` modules for dev/staging/prod and `infra/apim` policy files.
- [ ] Add `prompts/` backend resources seeded with behavior-equivalent copies of the v1
  prompt policy. Preserve behavior in Phase 5, but separate reviewed policy/task rules,
  explicit user instruction, personalization, and quoted untrusted field/conversation
  content into distinct messages/content parts. Quality changes wait for Phase 6.
- [ ] Prohibit provider tools and arbitrary client-selected URLs/models/templates; apply
  closed schema/enum validation to classifier, Prompt Builder, output mode, and route
  outputs before they affect orchestration or preview behavior.
- [ ] Add container health/readiness endpoints that disclose no secrets or dependency
  details.

### PostgreSQL baseline

- [ ] Provision Azure Database for PostgreSQL Flexible Server with private connectivity,
  enforced TLS, backups/PITR, and environment-specific sizing.
- [ ] Decide and provision the production CMK mode before production server creation;
  configure Key Vault protection, rotation/expiry alerts, and recovery ownership.
- [ ] Create initial migrations for:
  - `users`, `auth_identities`;
  - `organizations`, `organization_memberships`;
  - `devices`;
  - `privacy_preferences`;
  - `inference_requests`, `quota_reservations`;
  - `usage_ledger`, `usage_balances`, `pricing_versions`;
  - `entitlement_grants`, `entitlement_projection` with a free-alpha grant source;
  - `outbox_events`.
- [ ] Add foreign keys, unique constraints, check constraints, immutable/append-only
  enforcement for ledger records, and indexes for request/entitlement paths.
- [ ] Add `organization_id` and row-level security to tenant-owned tables; set tenant
  context transaction-locally and retain explicit tenant predicates in queries. Apply
  `FORCE ROW LEVEL SECURITY` and test pooled connections for tenant-context bleed.
- [ ] Use separate application and migration DB identities with least privilege. The
  runtime role neither owns tenant tables nor has `BYPASSRLS`.

### Azure skeleton

- [ ] Provision a VNet/subnets, private DNS, Container Apps environment, Container
  Registry, API Management Standard v2, PostgreSQL, Key Vault, App Configuration,
  a separate least-privilege Azure Storage deletion registry outside PostgreSQL's
  restore domain, monitoring, and budget/alert resources through Bicep.
- [ ] Create a workload-profiles Container Apps environment on a custom VNet with an
  internal VIP/public network disabled. Configure the API app with app-level
  `external=true` ingress (external to the environment) and managed identity; do not use
  app-level internal ingress, which APIM cannot reach from outside that environment.
- [ ] Put APIM Standard v2 outbound VNet integration in its delegated subnet and link
  private DNS so the Container Apps environment wildcard domain resolves to its internal
  static IP.
- [ ] Keep dev/staging/prod identity, data, secrets, Stripe mode, and provider resources
  isolated.
- [ ] Ensure deployed configuration contains no credential in source/Bicep parameters;
  use workload identity/managed identity and secret references where necessary.

### CI and observability

- [ ] CI runs TypeScript build/lint/unit tests, DB migration up/down/forward tests,
  OpenAPI/schema compatibility, Bicep validation, container/dependency/secret scans, and
  prompt-resource integrity checks.
- [ ] Deploy dev automatically and staging through approval; production deployment is
  disabled until later phase gates.
- [ ] Add structured logging with content keys rejected by a logger allowlist.
- [ ] Add metrics for request states, auth failures, latency, provider calls, token/cost
  counts, quota reservations, and DB health without request content.

**Accept:** a clean dev deployment creates the full private skeleton from IaC; an APIM
smoke test reaches the Container App through private DNS; the API reaches PostgreSQL;
migration/health checks pass; and direct internet attempts to the Container App or
PostgreSQL fail.

**Suggested commit:** `phase5.1: scaffold private API platform and PostgreSQL`

## Stage 5.2 — Real-user authentication and account/device state

### Entra External ID (web-side confidential client — ADR-0011)

- [ ] Create separate External ID configurations/app registrations for local development,
  staging, and production, all owned by the **web app** (confidential client).
- [ ] Do **not** register the macOS app as an Entra client. It has no redirect URI and no
  Entra client ID; it never presents an Entra token.
- [ ] Register the WriterFlow API audience/scope the web app requests from Entra during
  sign-in; document issuer/audience/scope as non-secret config and never accept arbitrary
  issuer metadata from a request.
- [ ] Configure an initial web user flow with email one-time passcode and the selected
  first social provider; keep the web client secret server-side only.

### WriterFlow device-token issuer (ADR-0012)

- [ ] Generate an asymmetric signing key in Key Vault; publish
  `api.writerflow.app/.well-known/jwks.json` and mint short-lived access tokens
  (`iss=https://api.writerflow.app`). Support key rollover.
- [ ] Issue opaque refresh tokens stored hashed and bound to one `devices` row; rotate on
  every use with reuse detection (a replayed refresh revokes the session family).
- [ ] Implement `POST /v2/device/authorize` (unauthenticated, rate-limited, stores a PKCE
  `code_challenge` against a single-use `device_code` + short `user_code`),
  `POST /v2/device/approve` (web-session-authenticated device binding + provisioning), and
  `POST /v2/device/token` (PKCE-bound poll returning tokens), plus `POST /v2/token/refresh`.

### macOS session (no MSAL)

- [ ] Add a `DeviceSessionProviding` implementation using `URLSession` + a small pairing
  state machine; no MSAL dependency, no OAuth client, no `ASWebAuthenticationSession`.
- [ ] `beginPairing()` calls `/v2/device/authorize`, shows the `user_code`, and offers to
  open the browser via `verification_uri_complete` (deep-link happy path) with manual
  `writerflow.app/pair` code entry as fallback.
- [ ] Register a `writerflow://paired` scheme in `Info.plist` only as a foreground hint to
  end the polling wait; verify it carries no token and that pairing succeeds without it.
- [ ] Store the WriterFlow access + refresh tokens in the app's own Keychain item
  (`WhenUnlockedThisDeviceOnly`, no access group). Local DB keys remain a separate item.
- [ ] Implement poll/backoff (`interval`, `slow_down`), refresh on explicit API need,
  sign-out, expired/revoked/denied handling, and cancellation.
- [ ] On refresh-token loss/rebuild, present a re-pair action — never silent data loss and
  never a touch to the local DB key.
- [ ] Do not begin pairing, poll, or refresh because of passive typing or focus events.
- [ ] Add device-session state to the dependency container instead of reading global
  Keychain readiness flags from `AppDelegate`.

### Server provisioning and authorization

- [ ] Configure APIM generic `validate-jwt` against **WriterFlow's own** JWKS/issuer
  (`https://api.writerflow.app`)/audience/expiry/scope — not Entra metadata, and not
  `validate-azure-ad-token`. Cache JWKS while allowing normal signing-key rollover.
- [ ] The web app validates Entra tokens server-side using a maintained library and the
  immutable `(issuer, subject)` identity key before calling `/v2/device/approve`.
- [ ] `POST /v2/device/approve` performs the former `/v2/bootstrap` work: in one
  idempotent transaction it creates the user, auth identity, personal organization, owner
  membership, and the `devices` record bound to the approved `device_code`.
- [ ] `/v2/me` and device list/revoke operations require a valid WriterFlow token + the
  non-revoked device ID and can affect only the current user's records.
- [ ] Every authenticated request rejects disabled user, inactive membership, and revoked
  device before business work. Treat the device ID as inventory/soft admission; a stolen
  token is answered by device/refresh-family revoke or account disable.
- [ ] `/v2/device/authorize` and `/v2/device/token` are the only bearer-exempt user
  routes; gate them with the PKCE-bound `device_code` and strict rate/body limits.
- [ ] Never join login and billing by email.

### UI

- [ ] Replace the BYO-Azure readiness onboarding card with Sign in/Account status for the
  v2 feature-flag cohort; permission onboarding remains separate and non-blocking.
- [ ] Add Dashboard Account and Devices cards with sign-in, sign-out, last-used device,
  revoke, and safe error states.
- [ ] Keep local history/personalization readable when signed out; inference is disabled
  with a clear sign-in action.

### Tests

- [ ] Unit/contract tests for pairing state transitions, poll backoff/`slow_down`,
  `expired_token`/`access_denied`, refresh rotation + reuse-detection revocation, and
  Keychain read/write without an access group.
- [ ] Device-code security tests: single-use `device_code`, PKCE `code_verifier` binding,
  `user_code` guessing/rate-limit resistance, and expiry.
- [ ] Integration tests for missing, malformed, wrong-issuer, wrong-audience, wrong-scope,
  expired, and valid WriterFlow tokens at the edge; and Entra token validation web-side.
- [ ] Cross-user tests for `/me` and device read/revoke.
- [ ] Verify secrets/tokens never appear in macOS/backend logs or diagnostics exports.

**Accept:** a new user signs in in the browser, approves the device, and `/v2/device/token`
returns a WriterFlow token; `/v2/device/approve` idempotently creates exactly one personal
organization/membership/current device; `/v2/me` returns it; API calls reject every
invalid-token case; revoking the device or refresh family blocks the cooperative
installation's next call; account disable covers stolen-token tests; and local data
remains available after sign-out/offline.

**Suggested commit:** `phase5.2: add browser pairing, device tokens, and account state`

## Stage 5.3 — Encrypted, account-scoped local data

The SQLCipher packaging spike may run after Stage 5.0 in parallel with backend work.
Runtime account binding and migration must wait for Stage 5.2's immutable issuer/subject
identity and device-approval provisioning flow.

### SQLCipher feasibility gate

- [ ] Time-box an SPM + GRDB + SQLCipher build spike for Debug/Release, app bundling,
  hardened signing, architecture verification, and an empty encrypted DB open/read/write.
- [ ] Own and pin the required GRDB Swift-package fork/manifest, assign upstream and
  SQLCipher security-update responsibility, and prove SQLCipher is the only linked
  SQLite implementation for every advertised Release architecture.
- [ ] Confirm no conflicting system SQLite/SQLCipher symbols and include all required
  licenses/notices.
- [ ] Record binary size, startup/query cost, packaging impact, and maintenance owner.
- [ ] If the spike fails, stop and approve a replacement ADR for CryptoKit AES-GCM field
  encryption and deliberately designed blind indexes before implementing persistence
  changes. Record its metadata/schema leakage and loss of general FTS/search explicitly.

### Store refactor

- [ ] Add a pre-store `LaunchCoordinator` that detects content-free binding/legacy state
  before constructing Dashboard view models or any account store. Refactor the current
  eager `AppDelegate → SettingsStore.shared → ConversionEventStore.shared →
  WriterFlowDatabase.shared` chain so it cannot open plaintext data before the migration
  lock.
- [ ] Replace `WriterFlowDatabase.shared` with an injected account-scoped database owner
  that has explicit `opening`, `ready`, `locked`, `migrationRequired`, `recoveryRequired`,
  and `failed` states.
- [ ] Generate a random 256-bit local database key from system randomness and store it in
  a dedicated account-scoped `WhenUnlockedThisDeviceOnly` Keychain item.
- [ ] Do not derive the DB key from password, OAuth token, refresh token, email, or network
  state.
- [ ] Remove the production silent in-memory fallback on DB open/migration failure.
- [ ] Move voice profile and recent custom instructions from plaintext UserDefaults into
  encrypted tables.
- [ ] Namespace history, memory, app rules, profile, usage cache, and custom history by
  account. Keep content-free compatibility diagnostics global.
- [ ] Bind one immutable `(issuer, subject)` account to the macOS profile; retain an
  opaque last-bound hash so its encrypted store opens offline/signed out.
- [ ] Reject a different identity with a clear sign-back-in or explicit
  export/remove/rebind choice. Do not implement silent account switching in v2.0.

### V1 atomic migration

- [ ] Detect the exact v1 plaintext/global data shape without modifying it.
- [ ] Persist an idempotent content-free marker recording which account consumed the
  one-time legacy migration; never copy the legacy store into another identity.
- [ ] Verify free space and prepare a separately encrypted rollback archive/key before
  migration; never leave the successful rollback artifact as plaintext SQLite.
- [ ] Export to a distinct encrypted temporary DB; never assume applying a passphrase
  encrypts the existing SQLite file.
- [ ] Migrate conversions, memory notes, app rules, voice profile, recent custom
  instructions, and retention settings.
- [ ] Run cipher integrity checks plus row counts/foreign keys/domain invariants, reopen
  with the Keychain key, then atomically swap.
- [ ] Remove plaintext UserDefaults content only after successful reopen.
- [ ] Exclude the encrypted rollback archive from diagnostics/backups, keep it only for a
  hard documented window, and delete both it and its distinct Keychain key through a
  verified cleanup step.
- [ ] Support cancellation before swap and recovery after interruption at every step.

### Tests

- [ ] Fixture migration from a real-shape v1 DB with all tables and settings.
- [ ] Fresh install and repeated/idempotent migration.
- [ ] First-account bind, sign-out/offline reopen, different-identity rejection,
  destructive rebind confirmation, and proof that legacy data migrates only once.
- [ ] Forced termination at each migration checkpoint.
- [ ] Wrong/missing Keychain key, locked Keychain, disk full, corrupt source, corrupt temp,
  insufficient permissions, and failed atomic swap.
- [ ] Missing-key UI offers only retry/unlock, valid matching export restore if
  implemented, or explicitly confirmed local reset; it never generates a new key and
  presents an empty database as recovered history.
- [ ] Artifact/string scan confirms representative history/profile plaintext is absent
  from the encrypted DB, UserDefaults, temporary/rollback files, and SQLite WAL/SHM
  artifacts after migration.
- [ ] Upgrade/key-reopen tests cross at least two ad-hoc-signed release-style builds
  (ADR-0010, no Developer ID) so Keychain/database continuity — and device-token
  re-pair-on-loss behavior — is verified for the real distribution shape, not debug runs.
- [ ] Dashboard search, filters, reactive observations, retention, Clear History, memory,
  app rules, and diagnostics still work.

**Accept:** existing v1 data survives an atomic, interruption-safe migration into an
encrypted account store; all local feature tests pass; a missing key yields a recovery
screen rather than empty data; no user-content settings remain in plaintext UserDefaults.

**Suggested commit:** `phase5.3: encrypt and account-scope the local GRDB store`

## Stage 5.4 — Private Azure inference relay and native transport parity

### Minimum accounting prerequisite

These items land before the first Azure model call; Stage 5.5 hardens and generalizes
them rather than introducing metering after provider traffic already exists.

- [ ] In one transaction create `inference_requests`, a worst-case
  `quota_reservation`, and a pending `usage_ledger` attempt under unique
  `(user_id, idempotency_key)` before provider access.
- [ ] Enforce the minimum request-state transitions and a free-alpha allowance so a
  duplicate or over-quota operation cannot reach Azure.
- [ ] On every success/failure/cancel/disconnect, commit provider usage/internal cost or
  release the reservation as applicable. Content never enters these rows.
- [ ] Make the first Fix Grammar vertical slice prove one operation, one provider
  attempt, and one immutable ledger attempt before expanding action parity.

### Azure model plane

- [ ] Provision at least one dev/staging Azure OpenAI resource/deployment reachable by
  private endpoint and private DNS only.
- [ ] Disable public network access and verify internet calls to the resource fail.
- [ ] Grant the Container App managed identity only the required inference role.
- [ ] Remove Azure API-key use from the WriterFlow backend path; if a temporary provider
  secret is unavoidable in dev, keep it in Key Vault and forbid it in app/artifacts.
- [ ] Add hard Azure budget, quota, and anomaly alerts.

### Server inference endpoint

- [ ] Implement `/v2/inference/stream` for an explicit v1 action, beginning with Fix
  Grammar as the vertical slice.
- [ ] Validate auth, device, entitlement, input schema/size, idempotency, concurrency, and
  quota reservation before provider access.
- [ ] Compile prompts from server resources with behavior parity to current
  `PromptBuilder`/`Prompts`; record prompt version, not content.
- [ ] Stream typed SSE lifecycle events and provider text deltas.
- [ ] Configure APIM `forward-request buffer-response="false"`, no response cache, and no
  request/response body logging for SSE.
- [ ] Send keepalive events if an allowed operation could be idle near platform timeout.
- [ ] Sanitize provider errors and never return upstream body/resource/deployment details.
- [ ] Cancel provider work promptly when the client cancels/disconnects where the SDK and
  platform permit.

### Native transport

- [ ] Add `InferenceTransport` and `WriterFlowAPIClient` without rewriting AX extraction,
  preview, or text insertion.
- [ ] Convert typed server events into the current `ActionEngine` callbacks/preview state.
- [ ] Send a new operation/idempotency UUID for each explicit action and Retry.
- [ ] Reuse current context extraction rules and caps; send no full AX tree.
- [ ] Preserve the client refocus guard before Replace and cancellation on new action.
- [ ] Add safe sign-in, plan, quota, rate-limit, timeout, unavailable, and conflict copy.
- [ ] Keep `BYOInferenceTransport` behind a non-production/beta rollback feature flag;
  ensure transport selection happens before an operation and cannot fan out.

### Expand parity

- [ ] Add Formal, Casual, Elaborate, Reply, Custom, Prompt Builder analyze/finalize,
  recommendation classification, and explicit style analysis through the same API.
- [ ] Preserve Custom `---INSERT---` behavior, preview variants policy, terminal context
  restriction, conversation caps/cache, output sanitizer, and provider usage capture.
- [ ] Remove client endpoint/deployment names from requests and user-visible responses.

### Tests

- [ ] Contract/SSE parser tests for split frames, comments/keepalive, unknown events,
  malformed JSON, provider error, clean completion, disconnect, and cancellation.
- [ ] Disconnect tests before first delta, mid-stream, and after server completion prove
  partial output cannot be applied, provider cost is reconciled, customer-unit policy is
  deterministic, same-key status does not call Azure, and Retry uses a new linked ID.
- [ ] Integration tests through APIM, not only direct origin calls.
- [ ] Canary-content test proves no body logging at APIM, API, monitor, or DB.
- [ ] End-to-end target-app matrix for every current action and Replace/Copy/Retry/Discard.
- [ ] Verify no duplicate provider call when the network drops, preview retries, app
  reopens, or the user invokes actions rapidly.

**Accept:** every existing v1 action works through the authenticated WriterFlow API with
equivalent output/stream/preview/replace behavior; origin/provider are unreachable from
the internet; the release client contains no Azure endpoint/key/deployment; content is
absent from telemetry and cloud persistence.

**Suggested commit:** `phase5.4: route v1 actions through private Azure SSE service`

## Stage 5.5 — Hardened accounting, quotas, reconciliation, and multi-model routes

### Request/usage accounting

- [ ] Generalize Stage 5.4's minimum request/reservation/ledger transaction across every
  classifier, enhancer, generator, Prompt Builder, and style-analyzer attempt.
- [ ] Harden unique `(user_id, idempotency_key)` handling and database-enforced state
  transitions under concurrent duplicate requests.
- [ ] Record one pending/committed/released usage record per provider attempt and logical
  stage, including failed/fallback attempts.
- [ ] Reconcile from provider-reported usage; store logical route, internal target ID,
  prompt version, input/output/cached/reasoning token fields as available, latency,
  provider cost micros, pricing version, and billable units—never text.
- [ ] Commit/release reservations and update `usage_balances` transactionally.
- [ ] Add an append-only constraint/API: corrections are reversing ledger entries, not
  mutation of committed rows.
- [ ] Add per-user/org request, concurrency, token/unit, and hard spend limits independent
  of APIM's burst protection.

### Logical route configuration

- [ ] Define server-only routes for `classifier_fast`, `grammar_fast`,
  `rewrite_standard`, `rewrite_premium`, `prompt_enhancer`, and `style_analyzer`.
- [ ] Map each route to one or more targets with region, priority, health, timeout,
  capability, cost, and allowed entitlement.
- [ ] Store non-secret target mapping in App Configuration/versioned deploy config; no
  arbitrary remote config URL exists in the Mac app.
- [ ] Implement health/circuit-breaker state and failover only before first delta.
- [ ] Return logical route/allowance labels only.
- [ ] Add an explicit `quality retry` signal that may select premium only when entitled;
  normal retries must not silently escalate cost.

### Reconciliation and operations

- [ ] Scheduled job reconciles stuck reservations/running requests and alerts on mismatch.
- [ ] Provider invoice/cost comparison report groups by logical route and pricing version.
- [ ] Dashboard `/v2/usage/current` returns allowance projection without raw provider
  pricing or editable client estimates.
- [ ] Run simulated concurrent requests to prove the hard quota cannot be exceeded beyond
  the documented reservation bound.

**Accept:** every provider attempt maps to one immutable ledger stage, repeated operation
keys do not repeat model work, quotas hold under concurrency, logical target changes need
no app update, and target failure before first delta safely falls back without duplicate
successful output.

**Suggested commit:** `phase5.5: add idempotent usage ledger and Azure route pools`

## Stage 5.6 — Upgrade alpha, feature flags, and Phase 5 validation

### Upgrade and settings

- [ ] On v1 upgrade, leave the legacy BYO key untouched until signed-in cloud inference
  succeeds.
- [ ] Add server-controlled cohort flags with local safe defaults for cloud transport,
  route pools, and paid enforcement. Feature flags cannot enable passive inference.
- [ ] Show Account/Cloud Service state in Dashboard; move Azure endpoint/key/deployment
  UI under a clearly labeled migration-only advanced section for alpha.
- [ ] After successful migration test, offer explicit removal of the legacy BYO key and
  `models.json`; record completion locally without sending the old key anywhere.
- [ ] Make rollback select the BYO transport for subsequent operations only; never repeat
  or mirror the current operation.

### Security and artifact checks

- [ ] Extend release scanner for Stripe secret patterns, database URLs/passwords, Entra
  confidential-client secrets, Key Vault URIs if treated as private config, Azure
  provider endpoints/deployments, and legacy `.env` values.
- [ ] Verify release app network destinations are limited to External ID/browser auth,
  `api.writerflow.app`, documented update/static hosts, and required OS services.
- [ ] Verify APIM/origin/DB/Key Vault/Azure OpenAI network posture from inside and outside
  the VNet.
- [ ] Run cross-tenant, replay, quota-race, oversized-payload, prompt-injection boundary,
  and content-log canary tests.

### Live matrix

- [ ] Clean v2 install: permissions → sign in → first cloud rewrite.
- [ ] v1.0.0 upgrade with populated history, voice profile, memory, app rules, recent
  custom instructions, and a Keychain BYO key.
- [ ] Gmail Chrome/Safari, WhatsApp desktop/web, Slack, Mail, Notes, Notion, LinkedIn,
  ChatGPT/Claude/Cursor, terminal, fullscreen, Spaces, external display.
- [ ] Sign out/offline keeps local dashboard data readable and never queues inference.
- [ ] Device revoke, account disable, expired token, quota exhaustion, provider outage,
  DB outage, Key Vault outage, and APIM timeout show clear safe behavior.
- [ ] p50/p95 edge/orchestrator overhead and first-delta latency captured by logical route.
- [ ] 8-hour Mac soak and service load/SSE soak; idle CPU/RSS v1 budgets retained.

### Alpha operational readiness

- [ ] Runbooks: auth outage, token signing-key rollover, DB restore, Key Vault/CMK
  recovery, provider target disable/failover, stuck reservation, usage mismatch, account
  disable/deletion, and feature-flag rollback.
- [ ] Alerts: auth failure anomaly, 5xx/latency, SSE disconnect, provider 429/quota,
  spend anomaly, ledger/reservation mismatch, DB/Key Vault health, and content-log canary.
- [ ] Privacy disclosure precisely states request-time content, optional personalization,
  transient backend decryption, provider processing, and what metadata is retained.

**Accept:** an opt-in alpha cohort upgrades without data/key loss, signs in, performs all
actions through the private service, can roll subsequent actions back without double
calls, sees accurate allowance state, and passes the security/network/live matrices.

**Suggested commit:** `phase5.6: complete secure v2 transport alpha migration`

## Phase 5 exit criteria

- [ ] All Stage 5.0–5.6 acceptance criteria pass.
- [ ] Direct Azure endpoint/key/deployment configuration is absent from the v2 production
  client path; BYO survives only as an explicitly time-limited alpha rollback.
- [ ] Entra user, personal organization, membership, and device provisioning are
  idempotent and cross-tenant safe.
- [ ] Existing local data is encrypted/account scoped and recovery tested.
- [ ] APIM is the only app-facing API ingress; Container Apps, PostgreSQL, Key Vault, and
  Azure OpenAI are private in staging/prod configuration.
- [ ] Every provider stage is idempotently metered and quotas are enforced server-side.
- [ ] Existing v1 actions, preview, Replace, focus safety, terminal safety, and
  explicit-action privacy pass the target-app matrix.
- [ ] No Stripe charge, subscription gate, auto-selection UX, or cloud history sync has
  been smuggled into this phase.
- [ ] Phase 6 can begin from transport parity, a stable API contract, and real latency/
  cost telemetry.

## Known implementation hazards

- GRDB + SQLCipher under Swift Package Manager requires an owned/pinned package fork or
  manifest adaptation; assign security-update ownership and prove the exact Release
  toolchain/SQLite linkage before touching user data.
- The current database singleton silently falls back to memory; encryption makes that a
  data-loss illusion and it must be removed before migration.
- The current concrete client construction in `ActionEngine`, `RecommendationEngine`,
  and `PersonalizationViewModel` will otherwise create accidental direct-Azure paths.
- The current acceptance event is marked before text-write success in one Replace path;
  fix it before accepted events drive personalization or billing metrics.
- APIM response buffering/body diagnostics can break SSE and leak content; test the
  deployed gateway configuration, not just application code.
- Token validation at APIM is not tenant authorization; repeat user/device/membership/
  entitlement checks in the backend and DB boundary.
- A Stripe-ready schema is useful now, but implementing Stripe in Phase 5 would couple
  three high-risk migrations. Defer payment side effects until the transport ledger is
  trusted.

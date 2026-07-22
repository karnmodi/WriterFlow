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

- [x] Add `services/api`, `services/worker`, and `services/shared` as one TypeScript
  workspace with strict type checking, linting, unit tests, and locked dependencies. —
  npm workspaces, `tsconfig.base.json` (strict + `noUncheckedIndexedAccess` +
  `exactOptionalPropertyTypes`), `eslint.config.mjs` (`strictTypeChecked`), vitest per
  package. `npm run check` (lint + typecheck + build + test) passes.
- [x] Use Fastify for HTTP/SSE and a migration/query layer that preserves explicit SQL,
  transactions, constraints, and migration review. — `services/api/src/app.ts` (Fastify
  5); `services/api/migrations/*.cjs` are hand-written `pgm.sql(...)` migrations run
  through `node-pg-migrate`, not an ORM/query-builder abstraction.
- [x] Add `infra/bicep` modules for dev/staging/prod and `infra/apim` policy files. —
  `infra/bicep/main.bicep` + 10 modules; `infra/apim/*.xml` (base, pairing-exempt, SSE
  operation policies). `az bicep build`/`az bicep lint` pass with zero errors/warnings.
- [x] Add `prompts/` backend resources seeded with behavior-equivalent copies of the v1
  prompt policy. Preserve behavior in Phase 5, but separate reviewed policy/task rules,
  explicit user instruction, personalization, and quoted untrusted field/conversation
  content into distinct messages/content parts. Quality changes wait for Phase 6. —
  `prompts/manifest.yaml` (trust-class documentation) + `prompts/intents/*.md` +
  `prompts/common/**/*.md`, ported verbatim from `Sources/WriterFlow/Engine/{Prompts,
  PromptBuilder}.swift`. Deviation: Custom's `---INSERT---` marker instruction text is
  kept verbatim (model behavior unchanged); only its *parsing* relocates server-side
  per `Docs/contracts/fixtures/requests/action-custom-insert-mode.json`'s note, since
  the SSE contract requires `decision.outputMode` before any delta.
- [x] Prohibit provider tools and arbitrary client-selected URLs/models/templates; apply
  closed schema/enum validation to classifier, Prompt Builder, output mode, and route
  outputs before they affect orchestration or preview behavior. — no tool/URL/model
  field exists anywhere in `services/shared`'s Zod schemas or `prompts/schemas/
  decision.json`; every enum is closed (`z.enum`/`z.discriminatedUnion`, JSON Schema
  `enum`). Enforcement code (the router that reads these types) lands in Stage 5.4.
- [x] Add container health/readiness endpoints that disclose no secrets or dependency
  details. — `GET /healthz` (always ok, no dependency touch) / `GET /readyz` (checks
  the DB pool, returns only `{status}` — unit-tested to prove a DB error's connection
  string/host string never appears in the response body).

### PostgreSQL baseline

- [ ] Provision Azure Database for PostgreSQL Flexible Server with private connectivity,
  enforced TLS, backups/PITR, and environment-specific sizing. — code complete; cloud
  apply pending: no Azure subscription connected yet. `infra/bicep/modules/postgres.bicep`
  (private-only network by default outside dev, `require_secure_transport=on`,
  environment-sized SKU/storage/backup-retention) is written and `bicep build`-clean.
- [ ] Decide and provision the production CMK mode before production server creation;
  configure Key Vault protection, rotation/expiry alerts, and recovery ownership. — open
  decision, not yet made (tracked here, not just cloud-apply-pending): `postgres.bicep`
  currently defaults to platform-managed keys with an inline TODO; needs an explicit
  ADR before a real prod server is created, since Azure documents the mode cannot change
  after creation.
- [x] Create initial migrations for:
  - `users`, `auth_identities`;
  - `organizations`, `organization_memberships`;
  - `devices`;
  - `privacy_preferences`;
  - `inference_requests`, `quota_reservations`;
  - `usage_ledger`, `usage_balances`, `pricing_versions`;
  - `entitlement_grants`, `entitlement_projection` with a free-alpha grant source;
  - `outbox_events`.

  `services/api/migrations/001`–`008`. **Verified, not cloud-apply-pending**: ran the
  full `up` → `down 0` → `up` cycle against a real local `postgres:17-alpine` container
  (Docker) — all 8 migrations apply and reverse cleanly.
- [x] Add foreign keys, unique constraints, check constraints, immutable/append-only
  enforcement for ledger records, and indexes for request/entitlement paths. —
  `usage_ledger`/`pricing_versions` reject `DELETE` and reject `UPDATE` of any
  financial column via triggers (verified: a live `DELETE FROM usage_ledger` raised the
  expected `usage_ledger is append-only` error); `usage_ledger`'s `UPDATE` trigger
  carves out exactly one exception — nulling `user_id`/`organization_id` — for the
  account-deletion anonymization path in `Docs/v2-data-retention-policy.md`.
- [x] Add `organization_id` and row-level security to tenant-owned tables; set tenant
  context transaction-locally and retain explicit tenant predicates in queries. Apply
  `FORCE ROW LEVEL SECURITY` and test pooled connections for tenant-context bleed. —
  `services/api/migrations/008_row_level_security.cjs`; `services/api/src/db.ts`'s
  `withTenantContext` sets `app.tenant_id` via `SET LOCAL` inside one transaction per
  pooled connection checkout. Verified live: connecting as `writerflow_app` with a
  freshly generated random tenant id returns zero rows from `organizations` (RLS denies
  by construction — no matching predicate — rather than by an app-level filter).
- [x] Use separate application and migration DB identities with least privilege. The
  runtime role neither owns tenant tables nor has `BYPASSRLS`. —
  `services/api/migrations/001_roles.cjs` creates `writerflow_app`
  (`NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS`, no table ownership, grants only);
  `writerflow_migrator` (the Postgres superuser locally; a dedicated least-privilege
  migrator role via Bicep in staging/prod) owns every table and runs migrations.

### Azure skeleton

- [ ] Provision a VNet/subnets, private DNS, Container Apps environment, Container
  Registry, API Management Standard v2, PostgreSQL, Key Vault, App Configuration,
  a separate least-privilege Azure Storage deletion registry outside PostgreSQL's
  restore domain, monitoring, and budget/alert resources through Bicep. — code
  complete; cloud apply pending: no Azure subscription connected yet, and the user has
  Azure/Entra access but no Entra External ID (CIAM) tenant created yet (manual portal
  step). All modules exist under `infra/bicep/modules/` and `main.bicep` wires them
  together; `az bicep build`/`az bicep lint` both pass with zero errors/warnings.
- [ ] Create a workload-profiles Container Apps environment on a custom VNet with an
  internal VIP/public network disabled. Configure the API app with app-level
  `external=true` ingress (external to the environment) and managed identity; do not use
  app-level internal ingress, which APIM cannot reach from outside that environment. —
  code complete; cloud apply pending. `container-apps-env.bicep` (`vnetConfiguration.
  internal = true`) + `container-app-api.bicep` (`ingress.external = true`, user-assigned
  managed identity for ACR pull + future Key Vault access).
- [ ] Put APIM Standard v2 outbound VNet integration in its delegated subnet and link
  private DNS so the Container Apps environment wildcard domain resolves to its internal
  static IP. — code complete; cloud apply pending. `apim.bicep` (`virtualNetworkType:
  External`, VNet integration into the delegated `apim-outbound` subnet from
  `network.bicep`); private DNS zone + link for the Container Apps default domain is in
  `network.bicep`.
- [ ] Keep dev/staging/prod identity, data, secrets, Stripe mode, and provider resources
  isolated. — partially addressed in code (`environmentName` parameterizes SKU/sizing/
  backup retention per environment in `postgres.bicep`/`budget.bicep`); full isolation
  (separate subscriptions/resource groups/Entra app registrations per environment) is a
  cloud-apply-time decision, not something the Bicep alone proves.
- [x] Ensure deployed configuration contains no credential in source/Bicep parameters;
  use workload identity/managed identity and secret references where necessary. — no
  `@secure()` parameter in any module has a real default value; `postgres.bicep`'s
  `administratorPassword` defaults to `newGuid()` (dev-only, regenerates every deploy)
  with an inline comment that staging/prod must pass a Key-Vault-sourced value instead.
  `container-app-api.bicep` uses only user-assigned managed identity for registry pull.

### CI and observability

- [x] CI runs TypeScript build/lint/unit tests, DB migration up/down/forward tests,
  OpenAPI/schema compatibility, Bicep validation, container/dependency/secret scans, and
  prompt-resource integrity checks. — `.github/workflows/ci.yml`, 6 jobs. **Verified
  locally** (not just written): `npm run check` (build/lint/typecheck/test) passes;
  the exact migration up→down→up cycle the `migrations` job runs was run by hand against
  a real local Postgres container and passed; `az bicep build`/`lint` pass; both
  `services/api/Dockerfile` and `services/worker/Dockerfile` build successfully and the
  API image was smoke-run against the real local Postgres (`/healthz`/`/readyz` both
  200). `gitleaks`/`dependency-review`/`trivy` steps themselves were not run locally
  (they need the GitHub Actions environment) but reference well-established actions.
- [ ] Deploy dev automatically and staging through approval; production deployment is
  disabled until later phase gates. — not built this stage. No CD/deploy workflow
  exists yet; writing one now would be unverifiable without a connected Azure
  subscription/service principal, so it's deferred rather than shipped untested. Next
  concrete step once the Entra tenant + a target subscription exist.
- [x] Add structured logging with content keys rejected by a logger allowlist. — Fastify/
  pino `redact` paths in `services/api/src/app.ts` (defense-in-depth, keyed off
  `services/shared`'s `FORBIDDEN_LOG_FIELD_NAMES`) plus `services/shared/src/
  logging.ts`'s `toSafeInferenceLogFields` allowlist for the structured operation-log
  call sites Stage 5.4 will add.
- [ ] Add metrics for request states, auth failures, latency, provider calls, token/cost
  counts, quota reservations, and DB health without request content. — not built this
  stage; there are no request-state/auth/provider code paths to measure yet (those land
  in Stage 5.2/5.4). Revisit once those handlers exist rather than instrumenting empty
  routes now.

**Accept:** a clean dev deployment creates the full private skeleton from IaC; an APIM
smoke test reaches the Container App through private DNS; the API reaches PostgreSQL;
migration/health checks pass; and direct internet attempts to the Container App or
PostgreSQL fail. — **not yet met**: this requires an actual cloud deployment, which is
cloud-apply-pending end to end (Azure/Entra credentials now available per the user, but
no Entra External ID tenant created yet and no `az deployment` has been run). Everything
gate-able without cloud access — code, migrations against a real local Postgres,
container builds/smoke-run, Bicep validation — is done and verified above.

**Suggested commit:** `phase5.1: scaffold private API platform and PostgreSQL`

## Stage 5.2 — Real-user authentication and account/device state

### Website hosting and scaffolding (V2-ARCHITECTURE.md §14)

Not an explicit phase-file checklist item originally, but a genuine blocker CLAUDE.md
flagged: "the website's static launch site ... has not yet been extended into the
confidential Entra client + /pair device-approval UI ... that conversion necessarily
drops static export for those routes and is still to be scoped when Stage 5.2 starts."
Scoped now (user decision, 2026-07-21): the website runs on **Azure Container Apps**, in
its own public environment separate from the API's internal-only one.

- [x] Convert `website/` off `output: "export"` — Next.js cannot mix static export with a
  dynamic route in one app, and `/pair` must be dynamic (a real session, eventually a
  client secret). `next.config.ts` now uses `output: "standalone"`. The three marketing
  pages (`/`, `/install`, `/privacy`) are unaffected in content or behavior — confirmed via
  `next build`'s route table, all three still render `○` (static, prerendered at build
  time), only `/api/health` and `/pair` are `ƒ` (dynamic). **Deviation, found and fixed**:
  an unpinned build root made Next infer the outer monorepo's `package-lock.json` as the
  workspace root during a local build, nesting the standalone server one directory deeper
  (`.next/standalone/website/server.js`) than an isolated Docker build (which only ever
  sees `website/`'s own files) would produce — a mismatch that would have silently broken
  `Dockerfile`'s `CMD ["node", "server.js"]` at deploy time despite looking fine in
  isolated local testing. Fixed by pinning `turbopack.root` explicitly in `next.config.ts`;
  confirmed a local `npm run build` now produces the un-nested layout Dockerfile expects
  (`.next/standalone/server.js` directly, not nested under a `website/` subdirectory) —
  the Docker build itself couldn't be run this session (see the note on the validate-build
  item below), so this fix is reasoned-through and locally consistent, not confirmed via
  an actual container build.
- [x] Add `website/app/api/health/route.ts` (Container Apps liveness/readiness probe
  target — no dependency checks, matching the probe's actual scope) and
  `website/app/pair/page.tsx` (reads the Mac app's `user_code`, renders sign-in/success/
  error states).
- [x] **`/pair` sign-in is real, not a stub** (user set up a real Entra External ID tenant
  and completed the flow end to end, 2026-07-22 — see "Real Entra sign-in wiring" below).
- [x] Add `website/Dockerfile` (multi-stage, mirrors `services/api/Dockerfile`'s shape) and
  `infra/bicep/modules/container-app-website.bicep` + a second `container-apps-env.bicep`
  instantiation with `internal: false` in `main.bicep` (`network.bicep` gained a matching
  new delegated subnet — Container Apps subnet delegation is one-environment-per-subnet,
  so this couldn't reuse the API's). **Deliberately NOT the same environment as the API**:
  that environment is `internal: true` with app-level `external: true` ingress meaning
  "external to the environment, not the internet" (Stage 5.1) — APIM is the only real
  public entry point to the API by design. Putting the website in the same environment
  would have required flipping the environment to public, silently exposing the API's own
  ingress to the raw internet too. `az bicep build`/`az bicep lint` clean. **Code complete;
  cloud apply pending**: no real deployment, no custom domain/TLS binding (needs a real DNS
  zone once one exists).
- [x] Rewrote `website/scripts/validate-export.mjs` → `validate-build.mjs` for the new
  build output shape (`.next/server/app/*.html` instead of a flat `out/` directory) and
  updated `package.json`'s `validate-build`/`check` scripts. Verified locally: `npm run
  check` (lint, typecheck, build, validate-build) passes in both release-candidate and
  `NEXT_PUBLIC_RELEASE_STATUS=available` modes. Also ran the actual standalone server
  produced by `next build` directly (`node .next/standalone/server.js`, not through
  Docker) and confirmed `/`, `/api/health/`, and `/pair/?user_code=...` all serve the
  expected content/status against a live running process, not just a static-file
  presence check. Updated `website/README.md` to describe the new dual static+dynamic
  shape honestly instead of claiming "no runtime server routes." **Not verified: the
  actual `docker build -f website/Dockerfile`.** Attempted it — `docker pull
  node:24-alpine` (and even a plain `docker pull alpine:latest`) both hung for 2+ minutes
  producing zero output in this sandboxed session before being killed; this reproduced
  identically outside the Dockerfile too, so it's this environment's network path to
  Docker Hub, not a problem with the Dockerfile itself. The Dockerfile's shape mirrors
  `services/api/Dockerfile` (already proven to build earlier this session) almost
  exactly, and the standalone-server behavior it wraps is independently verified above,
  but the image build itself is unverified — flag for a real `docker build` before first
  deploy, same as the layout bug the build-root fix above was specifically added to catch.
  **Not updated**: `website/app/privacy/page.tsx`'s copy still says "No WriterFlow account,
  membership, or subscription... No custom WriterFlow app-facing API" — this is now
  genuinely stale, not just pre-emptively so: `/pair` really does create an account as of
  the next item below. A product/legal-adjacent messaging decision that shouldn't be
  silently rewritten mid-infrastructure-change — flagging for the person who owns that
  copy.

#### Real Entra sign-in wiring (2026-07-22)

The user independently set up a real Entra External ID tenant, app registration, and
`.env.services`/`website/.env.local` config, then asked to wire up the actual sign-in
flow rather than continue with manual `curl`-based testing. Built:

- `website/lib/entra.ts` — server-only `openid-client` (`^6.8.4`) config via `discovery()`
  against the real tenant's issuer, rather than hand-fetching/hardcoding metadata.
- `website/app/pair/start/route.ts` — generates a PKCE pair, stores it with the device's
  `user_code` in a short-lived httpOnly cookie, redirects to Entra's authorize endpoint.
- `website/app/pair/callback/route.ts` — the Entra redirect target: exchanges the code for
  an ID token (`client.authorizationCodeGrant`, server-side — this specifically avoids the
  SPA-platform "cross-origin requests only" restriction hit during manual jwt.ms testing,
  since the exchange happens in Node, not the browser), then calls `POST /web-session/
  token` and `POST /device/approve` against `services/api`, never exposing either token to
  the browser.
- `services/api/src/app.ts` — registered `@fastify/cors` scoped to exactly
  `config.WEBSITE_BASE_URL` (no wildcard). Not actually required by the final server-side
  flow (server-to-server `fetch` calls aren't subject to CORS), but is a real gap this
  work surfaced: the API had no CORS support at all, and *some* future browser-side call
  from the website's origin is plausible. Left in as defense-in-depth, matching the
  non-wildcard-audience discipline used everywhere else in this service.

**Three real bugs found and fixed by actually running this against a live tenant, not
just reasoning about the code:**
1. `next.config.ts`'s leftover `trailingSlash: true` (a holdover from the `output:
   "export"` era) silently 308-redirected Entra's callback request to add a trailing
   slash *before* the route handler ran, so the `redirect_uri` `authorizationCodeGrant`
   inferred from the request URL no longer matched the one sent at the authorize step —
   Entra correctly rejected this as `AADSTS500112`. Removed `trailingSlash` entirely; the
   marketing pages serve identical content either way in server mode, so nothing depended
   on it. Caught by adding temporary `console.error` logging to the callback route once
   the generic on-page error message ("server responded with an error in the response
   body") proved too vague to diagnose from the browser alone.
2. Entra rejected the PKCE-only public-client token exchange for the Web platform
   redirect with `AADSTS7000218` ("must contain client_assertion or client_secret") — this
   particular app registration requires a client secret even with PKCE. User generated one
   in the portal and added `ENTRA_WEB_CLIENT_SECRET` to `website/.env.local`.
3. That secret was first saved as a *commented-out* line with a stray leading space
   (`# ENTRA_WEB_CLIENT_SECRET= <value>`), so it silently never loaded. Fixed by
   uncommenting and stripping the space — worth calling out only because it's exactly the
   kind of copy-paste error that produces a confusing downstream symptom (still
   `invalid_client`) rather than an obvious "secret is missing" one.

**Verified end to end, twice, against the real tenant** (not mocked): a device
authorized via a direct `POST /device/authorize` call (standing in for the Mac app,
which uses the identical protocol), a real interactive Microsoft sign-in completed in a
live browser session, `/pair` showed "Device approved," and a subsequent `POST
/device/token` poll for that same device returned a real WriterFlow access token —
proving the full chain (Entra sign-in → ID token → web-session token → device approve →
device token issuance) works, not just that individual steps don't error. `npm run
lint`/`typecheck`/`build` clean for both `website` and `services/api`; full
`services/api` suite still 47/47 against real Postgres. Not re-covered by automated
tests this increment (explicitly deferred per the user's request to prioritize getting
the flow working) — worth adding integration coverage for `/pair/start` and `/pair/
callback` before this is considered done for the stage, ideally with a fake/local
`EntraIdTokenVerifier`-style seam so it doesn't require a live tenant to run in CI.

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

- [x] Generate an asymmetric signing key in Key Vault; publish
  `api.writerflow.app/.well-known/jwks.json` and mint short-lived access tokens
  (`iss=https://api.writerflow.app`). Support key rollover. — `services/api/src/jwt/keys.ts`
  defines the `SigningKeyProvider` seam (kid-based, ready for multiple concurrently-valid
  keys during rollover) and `LocalDevSigningKeyProvider` (ES256, in-memory, dev-only —
  clearly documented as unsafe for any deployed environment). **Code complete; cloud
  apply pending**: the Key Vault-backed provider (private key never leaves Key Vault,
  signs via Key Vault's sign operation) isn't implemented — no Key Vault exists yet.
  `GET /.well-known/jwks.json` is live and verified (`services/api/src/routes/jwks.ts`,
  containerized smoke test returned a correct public-only ES256 JWK). Added the missing
  APIM piece this stage exposed: `infra/bicep/modules/apim.bicep`'s `writerflow-v2` API
  is mounted at path `v2`, but JWKS is a fixed RFC 8615 root path — added a second
  `writerflow-well-known` API at APIM's true root forwarding `/.well-known/jwks.json` to
  the same backend (`az bicep build`-clean; cloud apply pending).
- [x] Issue opaque refresh tokens stored hashed and bound to one `devices` row; rotate on
  every use with reuse detection (a replayed refresh revokes the session family). —
  `services/api/migrations/009_device_pairing.cjs` (`refresh_tokens` table, replacing
  migration 003's vestigial `devices.refresh_token_hash`/`refresh_token_family_id`
  columns with real per-token history) + `services/api/src/pairing/service.ts`'s
  `rotateRefreshToken`. **Verified against real Postgres**: rotation issues a new token
  and marks the old one superseded; replaying the superseded token is rejected AND
  revokes the whole family, invalidating the token that replaced it too (all covered by
  `services/api/test/integration/pairing.integration.test.ts`, run against a live
  `postgres:17-alpine` container as the `writerflow_app` role — not mocked).
- [x] Implement `POST /v2/device/authorize` (unauthenticated, rate-limited, stores a PKCE
  `code_challenge` against a single-use `device_code` + short `user_code`),
  `POST /v2/device/approve` (web-session-authenticated device binding + provisioning), and
  `POST /v2/device/token` (PKCE-bound poll returning tokens), plus `POST /v2/token/refresh`.
  — `services/api/src/routes/device.ts`, `services/api/migrations/009_device_pairing.cjs`
  (`device_authorizations` table). Verified end to end against real Postgres: pending →
  wrong-PKCE (`invalid_grant`) → issued → single-use replay (`expired_token`) →
  `slow_down` rate limiting → revoked-device rejection.

  **`/v2/device/approve`'s open design question is resolved** (user decision, 2026-07-19):
  a second WriterFlow-minted token issuer, distinct audience
  (`https://api.writerflow.app/web-session`) from the device access token, same
  signing/JWKS infrastructure as ADR-0012. New `POST /v2/web-session/token`: the website
  forwards the Entra ID token it already validated; `services/api/src/entra/
  verifier.ts`'s `EntraIdTokenVerifier` independently re-validates it against Entra's own
  JWKS (never trusts the website's say-so alone) and, only then, mints a 5-minute
  web-session token carrying the raw `(entra_issuer, entra_subject)` pair. `/device/approve`
  requires that token specifically — a device access token is structurally rejected
  (wrong audience), proven by a dedicated cross-audience test. `services/api/src/pairing/
  approve.ts` performs the idempotent provisioning transaction (user, auth identity,
  personal organization, owner membership, device, privacy preferences, a free-alpha
  `entitlement_grants`/`entitlement_projection` row) — verified against real Postgres:
  new identity, idempotent retry of an already-approved `user_code`, a returning identity
  reusing its existing user/org while getting a new device, unknown/expired `user_code`
  rejection, and RLS-invisibility of the freshly created organization without tenant
  context. **Code complete; cloud apply pending**: `EntraIdTokenVerifier.remote(...)` (the
  production path, fetching a real tenant's JWKS) is wired in `services/api/src/index.ts`
  behind `ENTRA_TENANT_ISSUER`/`ENTRA_JWKS_URI`/`ENTRA_WEB_CLIENT_ID`, all optional and
  unset — `/web-session/token` returns a safe 503 until the Entra tenant exists and those
  are configured; verified this exact behavior against the containerized image.

  **Two real bugs found and fixed while implementing this** (not just written — caught by
  testing against real Postgres, not mocks):
  1. `devices` has `FORCE ROW LEVEL SECURITY` keyed on `organization_id` (Stage 5.1,
     migration 008), but `/device/token` and `/token/refresh` must resolve a `devices` row
     from a bare device ID *before* any tenant context exists — that's what they're
     establishing. Unaddressed, this would have silently returned zero rows under
     `writerflow_app` in a real deployment despite working in every local test that
     happened not to exercise it. Fixed with `services/api/migrations/
     010_device_bootstrap_lookup_policy.cjs` (an additional session-flag-gated RLS policy,
     OR'd with the tenant policy — no role gets `BYPASSRLS`, the phase-wide non-negotiable
     holds) and `services/api/src/db.ts`'s `withDeviceBootstrapLookup`. Proven with a
     dedicated integration test that queries `devices` directly as `writerflow_app` with
     neither tenant context nor the bootstrap flag set and asserts zero rows.
  2. `current_setting('app.tenant_id', true)` does **not** reliably return `NULL` when
     unset: PostgreSQL resets a custom GUC to an empty string (not `NULL`) after the
     transaction that first `SET LOCAL`'d it commits, and that reset value persists on
     the pooled physical connection for any later transaction that doesn't set it again
     — exactly what happens when a `withTenantContext` call (e.g. inside `/device/approve`)
     is followed by a `withDeviceBootstrapLookup` call (e.g. inside `/device/token`) on a
     connection the pool reused. Every tenant-isolation RLS policy's `::uuid` cast then
     crashed with `invalid input syntax for type uuid: ""` instead of safely evaluating to
     false. Fixed in migration 008 with a `current_tenant_id()` SQL function that wraps
     the read in `NULLIF(..., '')` before casting; reproduced and confirmed against a real
     `psql` session before fixing, and the full test suite (including the exact
     approve-then-poll connection-reuse sequence that surfaces it) passes after the fix.
     `services/shared`/`services/api`'s own tests don't defend against this class of bug by
     construction — only exercising the real database, as the integration suite does, could
     have caught it.

### macOS session (no MSAL)

**Note on tooling**: this machine now has full Xcode installed (not just Command Line
Tools) as of this stage — `swift test`/`xctest` work and were used for real automated
coverage below, superseding CLAUDE.md's earlier "swift test may remain unavailable"
note (updated in the same commit as this stage's work).

- [x] Add a `DeviceSessionProviding` implementation using `URLSession` + a small pairing
  state machine; no MSAL dependency, no OAuth client, no `ASWebAuthenticationSession`. —
  `Sources/WriterFlow/Store/DeviceSession.swift` (protocol + `DeviceSessionState`/
  `PairingChallenge`/`DeviceSessionError`) and `DeviceSessionStore.swift` (the `actor`
  implementation), `WriterFlowAPIClient.swift` (plain `URLSession`, mirrors
  `AzureOpenAIClient`'s existing actor/async-await pattern). 21 unit tests in
  `Tests/WriterFlowTests/{DeviceSessionStoreTests,PKCETests,MacHardwareModelTests}.swift`
  pass via real `swift test` (mocked network via a new `MockURLProtocol` test helper).
- [x] `beginPairing()` calls `/v2/device/authorize`, shows the `user_code`, and offers to
  open the browser via `verification_uri_complete` (deep-link happy path) with manual
  `writerflow.app/pair` code entry as fallback. — the underlying mechanism is built and
  verified (`beginPairing()` returns a `PairingChallenge` with both URLs; a `#if DEBUG`
  menu item added to `AppDelegate` for this stage's manual verification calls
  `NSWorkspace.shared.open(challenge.verificationURIComplete)` successfully). **Actually
  showing the `user_code` to the user in production UI does not exist yet** — that's
  Stage 5.2's separate "UI" checklist (Sign in/Account status card), not started.
- [x] Register a `writerflow://paired` scheme in `Info.plist` only as a foreground hint to
  end the polling wait; verify it carries no token and that pairing succeeds without it. —
  `Info.plist`'s new `CFBundleURLTypes`; `AppDelegate.application(_:open:)` only checks
  `scheme`/`host` and never reads `url.query`/`url.fragment`. Verified by two tests:
  `testForegroundHintEndsThePollingWaitEarly` (a 5s poll interval ends in <4s once the
  hint fires) and `testPairingSucceedsWithoutEverCallingTheForegroundHint`.
  **Deviation, found and fixed mid-implementation**: the first version raced a
  `withCheckedContinuation` against `Task.sleep` inside `withTaskGroup` to implement the
  early-wake — cancelling the continuation's child task via `group.cancelAll()` never
  actually resumed it (cancellation doesn't force-resume a checked continuation), and
  `withTaskGroup` waits for every child task before returning, so the whole thing
  deadlocked forever. Caught because `swift test` really hung (~6 hours of wall-clock
  before being noticed and killed — a real lesson in checking on backgrounded test runs,
  not just trusting them to finish). Rewritten using a stored, cancellable `Task<Void,
  Never>` wrapping `Task.sleep` directly — cancellation of a sleeping `Task` correctly
  throws and lets it finish, with no dangling continuation.
- [x] Store the WriterFlow access + refresh tokens in the app's own Keychain item
  (`WhenUnlockedThisDeviceOnly`, no access group). Local DB keys remain a separate item.
  — `Sources/WriterFlow/Store/DeviceTokenKeychain.swift`, a distinct Keychain
  service/account from `KeychainStore`'s BYO Azure key item. **Deviation, found and
  fixed**: the first version added `kSecUseDataProtectionKeychain: true` to every query,
  which isn't used anywhere in the existing (working) `KeychainStore.swift` pattern —
  read-after-write silently failed under `swift test`'s unsigned CLI binary (three tests
  failed with `notPaired` despite writing tokens immediately before reading them).
  Removed to match `KeychainStore`'s proven-working pattern exactly; all tests pass
  after.
- [x] Implement poll/backoff (`interval`, `slow_down`), refresh on explicit API need,
  sign-out, expired/revoked/denied handling, and cancellation. — all covered by
  `DeviceSessionStoreTests.swift`: `slow_down` extends the interval and still succeeds,
  `access_denied`/`expired_token` throw and reset to `.signedOut`, `accessToken()`
  refreshes only when within `expiryLeeway` of expiry (and proves zero network calls
  when the cached token is still valid), `signOut()` clears Keychain + state, and a new
  `cancelPairing()` method (added to `DeviceSessionProviding` this stage — the checklist
  explicitly named "cancellation" and there was no way to stop an in-flight poll before
  this) stops `awaitPairedToken()` early with a dedicated `.pairingCancelled` error.
- [x] On refresh-token loss/rebuild, present a re-pair action — never silent data loss and
  never a touch to the local DB key. — the state-machine half is done: `accessToken()`
  never clears the Keychain item on refresh failure (only an explicit `signOut()` does),
  and moves to a distinct `.needsRePair` state rather than silently reverting to
  `.signedOut` (tested). **The "present a re-pair action" UI does not exist yet** — same
  Stage 5.2 UI checklist gap as `beginPairing()`'s user_code display above. There is no
  separate local DB key concept yet either (that's Stage 5.3).
- [x] Do not begin pairing, poll, or refresh because of passive typing or focus events. —
  true by construction: every `DeviceSessionProviding` entry point requires an explicit
  caller; nothing in `FocusMonitor`/`OverlayController` references `DeviceSessionStore`,
  and `init` performs a local Keychain read only, no network call.
- [x] Add device-session state to the dependency container instead of reading global
  Keychain readiness flags from `AppDelegate`. — `AppDelegate` now holds one
  `deviceSession: DeviceSessionProviding` property and would query `deviceSession.state`
  wherever v2 auth-gated UI needs it, rather than the scattered ad hoc
  `KeychainStore.hasConfiguredAPIKey()`-style checks the existing v1 BYO-key path still
  uses (that v1 path is unchanged — out of scope for this stage). No broader
  `AppDelegate` dependency-injection refactor was attempted; that's Stage 5.3's
  `LaunchCoordinator`/account-scoped-store work (V2-ARCHITECTURE.md §4.2), a different
  and larger scope than this checklist item asks for.

### Server provisioning and authorization

- [ ] Configure APIM generic `validate-jwt` against **WriterFlow's own** JWKS/issuer
  (`https://api.writerflow.app`)/audience/expiry/scope — not Entra metadata, and not
  `validate-azure-ad-token`. Cache JWKS while allowing normal signing-key rollover.
- [ ] The web app validates Entra tokens server-side using a maintained library and the
  immutable `(issuer, subject)` identity key before calling `/v2/device/approve`.
- [x] `POST /v2/device/approve` performs the former `/v2/bootstrap` work: in one
  idempotent transaction it creates the user, auth identity, personal organization, owner
  membership, and the `devices` record bound to the approved `device_code`. —
  `services/api/src/pairing/approve.ts`; see the device-token-issuer bullet above for the
  full verification summary and the two bugs it caught.
- [x] `/v2/me` and device list/revoke operations require a valid WriterFlow token + the
  non-revoked device ID and can affect only the current user's records. —
  `services/api/src/auth/guard.ts`'s `requireDeviceAuth` (verifies the bearer token, then
  re-checks `devices.revoked_at`/`users.status` live against the DB, not just at
  token-mint time) backs both `services/api/src/routes/account.ts` routes: `GET /me`
  (`account/service.ts`'s `getAccountSnapshot`) and `DELETE /devices/:id`
  (`revokeDevice`, scoped by `user_id = ctx.userId` so ownership is enforced in the query
  itself, not just checked after the fact). `revokeDevice` also revokes any still-active
  `refresh_tokens` row for that device, so a stolen refresh token stops working
  immediately rather than only once its access token expires. Verified against real
  Postgres by 7 new tests in `services/api/test/integration/account.integration.test.ts`:
  happy-path `/me` (including that the device label captured at `/device/authorize` was
  actually persisted — see the bug note below), missing/garbage-token 401s, cross-device
  revoke within the same user (revoked device's own token now rejected, the revoking
  device's token still works), revoke-also-kills-refresh-token (subsequent
  `/token/refresh` returns 401), and cross-user revoke returning 404 without touching the
  victim's device. **Bug found and fixed while building this**: `install_metadata` (and
  therefore the device label) was never actually written during provisioning even though
  `/device/authorize` captured it — `approveDevice`'s two provisioning paths
  (`provisionDeviceForExistingUser`/`provisionNewUser` in `services/api/src/pairing/
  approve.ts`) now thread `device_authorizations.device_label` through to
  `devices.install_metadata`, read back via `install_metadata->>'label'`.
- [x] Every authenticated request rejects disabled user, inactive membership, and revoked
  device before business work. Treat the device ID as inventory/soft admission; a stolen
  token is answered by device/refresh-family revoke or account disable. — the previously
  noted gap is closed: `pollDeviceToken` and `rotateRefreshToken`
  (`services/api/src/pairing/service.ts`) now JOIN `users` and reject
  (`invalid_grant`/`invalid` respectively) when `user_status !== "active"`, not only when
  `devices.revoked_at` is set, and `requireDeviceAuth` performs the same live check on
  every `/me`/`/devices/:id` call. Verified against real Postgres: a device paired while
  the user was active, then the user is set to `disabled` directly in the DB — `/me`
  correctly returns 403 `AUTH_INVALID` rather than succeeding on the still-valid access
  token. Inactive membership still has nothing to check (only one membership role model
  exists, no suspend-membership action implemented) — not a regression, just not yet a
  feature that exists to gate on.
- [x] `/v2/device/authorize` and `/v2/device/token` are the only bearer-exempt user
  routes; gate them with the PKCE-bound `device_code` and strict rate/body limits. —
  `services/api/src/routes/device.ts` requires no bearer for any of `/device/authorize`,
  `/device/token`, `/token/refresh` (matching `security: []` on all three in
  `Docs/contracts/openapi.yaml`); `/device/token` and `/token/refresh` are instead gated
  by their own opaque, single-use/rotating credentials. `infra/apim/pairing-operations-
  policy.xml` (Stage 5.1) still needs wiring to the actual APIM operations once those
  exist in Bicep — tracked as a Stage 5.2 infra follow-up alongside the JWKS API just
  added, not done this stage (no APIM operations resources exist for the `v2` API yet,
  only the API-level base policy).
- [x] Never join login and billing by email. — true by construction: identity is
  resolved solely by the immutable `(issuer, subject)` pair in `auth_identities`
  (`services/api/src/pairing/approve.ts`); no code path in `pairing/`, `account/`, or any
  migration through `011` reads, stores, or joins on an email address. Billing/Stripe
  itself is out of Phase 5 scope (see the phase-wide scope note above), so there is
  nothing yet to join against — revisit this item when Stripe customer linkage is built,
  to confirm it also keys off `organization_id`/`user_id`, not email.

### UI

- [ ] Replace the BYO-Azure readiness onboarding card with Sign in/Account status for the
  v2 feature-flag cohort; permission onboarding remains separate and non-blocking. —
  **deliberately not done this way**: no real cohort-assignment mechanism exists yet (that's
  entitlement-driven, Stage 5.4 territory), and swapping out v1's primary onboarding gate
  before sign-in can actually complete end to end (no Entra tenant, no website `/pair` page
  yet) would risk breaking v1 BYO-Azure users for no working replacement. Built the Account
  card (next item) as a new, additive Dashboard tab instead — v1's onboarding flow
  (`OnboardingView`/`OnboardingWindowController`, the `needsAzureSetup` gate in
  `AppDelegate.applicationDidFinishLaunching`) is completely untouched. Revisit this
  specific item once there's a real cohort flag to gate the replacement on.
- [x] Add Dashboard Account and Devices cards with sign-in, sign-out, last-used device,
  revoke, and safe error states. — `Sources/WriterFlow/Dashboard/{AccountView,
  AccountViewModel}.swift` + `Sources/WriterFlow/Store/AccountService.swift` (new — composes
  `DeviceSessionProviding` token lifecycle with `WriterFlowAPIClient`'s new `me()`/
  `revokeDevice()` calls, kept separate from `DeviceSessionProviding` itself since that's
  only about token state, not account data). Added as a new "Account" tab in
  `DashboardChrome.DashboardTab`/`DashboardView`, threaded through
  `DashboardWindowController`/`AppDelegate` via the existing `deviceSession` property (no
  new dependency-injection plumbing needed). Only a single **device** card, not a **devices**
  list — `Docs/contracts/openapi.yaml`'s `AccountSnapshot`/`/me` only ever describes the
  calling device itself (`device: Device`, singular; there is no list-devices endpoint in
  the contract), so a multi-device list would be inventing API surface that doesn't exist
  server-side. States covered: idle/loading, signed-out (Sign In button), pairing
  (`user_code` shown, browser auto-opened via `NSWorkspace`, re-open/cancel actions),
  signed-in (device label, plan, monthly units, sync status, Sign Out, and a destructive
  "Revoke This Device" that also always signs out locally even if the server call fails —
  see `AccountService.revokeCurrentDeviceAndSignOut()`), needsRePair (re-sign-in prompt),
  and a generic error state with retry. Every button action is `async` on `AccountViewModel`
  (not an internal fire-and-forget `Task`), so `AccountView` wraps each in its own
  `Task { await ... }` — this made cancellation trivial to get right: `cancelSignIn()`
  calling `session.cancelPairing()` interrupts an in-flight `beginSignIn()`'s suspended
  `awaitPairedToken()` await via the MainActor's normal cooperative scheduling, no separate
  task-handle bookkeeping needed (contrast with the more complex `activeSleepTask` machinery
  `DeviceSessionStore` itself needed at the actor layer). Verified with 13 new unit tests
  (5 in `WriterFlowAPIClientAccountTests.swift` for the new `me()`/`revokeDevice()` HTTP
  calls — bearer header, GET has no body, 401/404 map to `httpError`; 8 in
  `AccountViewModelTests.swift` against a real `DeviceSessionStore` + `MockURLProtocol`,
  covering signed-out/signed-in refresh, refresh-token-failure → needsRePair, sign-out,
  revoke-then-signed-out on both success and server failure, full pairing → loaded, and
  mid-pairing cancellation) — full suite 69/69 (2 skipped live-integration tests, as
  before). `swift build`/`swiftlint` clean on every new/changed file. **Not verified**:
  actual on-screen rendering/click-through of `AccountView` in the running app — this
  session has no interactive display tooling to drive a native macOS UI (unlike the
  browser-automation tools available for web UI), so this is compile+unit-test verified
  only, not visually verified. Flag for manual verification.
- [ ] Keep local history/personalization readable when signed out; inference is disabled
  with a clear sign-in action. — the "readable when signed out" half is true by
  construction and unaffected by this stage's work (`HistoryView`/`PersonalizationView`
  read straight from the local GRDB store regardless of `DeviceSessionProviding.state`,
  and nothing added this stage touches them). The "inference is disabled with a clear
  sign-in action" half does not exist yet: v1's `ActionEngine` still calls BYO-Azure
  directly and has no dependency on `DeviceSessionProviding` at all — there is no v2
  inference path yet to gate on sign-in state. That wiring is Stage 5.3/5.4 territory
  (encrypted local data model, server-side model routing), not this stage.

### Tests

- [ ] Unit/contract tests for pairing state transitions, poll backoff/`slow_down`,
  `expired_token`/`access_denied`, refresh rotation + reuse-detection revocation, and
  Keychain read/write without an access group. — **backend + Keychain done, one gap
  remains**: pairing state transitions, `slow_down`, `expired_token`, and refresh
  rotation + reuse-detection are all covered by `services/api/test/integration/
  pairing.integration.test.ts` against real Postgres (`access_denied` — the "denied"
  device_authorizations status — has a code path in `pollDeviceToken` but no dedicated
  test yet, since nothing sets that status without `/device/approve`'s deny action
  existing, which nothing in the spec calls for building this stage). Keychain read/write
  without an access group is now directly tested: `Tests/WriterFlowTests/
  DeviceTokenKeychainTests.swift` (new) asserts `DeviceTokenKeychain.baseQuery()` —
  extracted as a small `internal` seam shared by `read()`/`write()`/`delete()` — never
  contains `kSecAttrAccessGroup`, plus write/read/overwrite/delete round-trips and
  independence from `KeychainStore`'s separate BYO-Azure-key item. 7 new tests, full
  suite 76/76 (2 skipped live-integration tests, unchanged), `swift build`/`swiftlint`
  clean.
- [x] Device-code security tests: single-use `device_code`, PKCE `code_verifier` binding,
  and expiry. — all three verified against real Postgres (replay after issuance returns
  `expired_token`; wrong verifier returns `invalid_grant`; a `device_code` past its
  `expires_at` returns `expired_token` even while otherwise still pending).
  `user_code` guessing/rate-limit resistance is APIM's job
  (`infra/apim/pairing-operations-policy.xml`'s IP-keyed rate limit, Stage 5.1) — not
  independently testable without a deployed APIM.
- [ ] Integration tests for missing, malformed, wrong-issuer, wrong-audience, wrong-scope,
  expired, and valid WriterFlow tokens at the edge; and Entra token validation web-side. —
  **code-level half done**: `services/api/test/jwt.test.ts` covers malformed,
  unknown-kid, wrong-issuer, wrong-audience, and expired tokens against
  `verifyAccessToken` (the application-layer check). The APIM `validate-jwt` edge itself
  can't be tested without a deployed APIM (cloud apply pending); Entra token validation
  web-side doesn't exist yet (no website work this stage) and there's no `scope` claim
  differentiation yet to test wrong-scope against.
- [x] Cross-user tests for `/me` and device read/revoke. — covered by
  `account.integration.test.ts`'s cross-device (same user) and cross-user revoke cases
  above, run against real Postgres.
- [x] Verify secrets/tokens never appear in macOS/backend logs or diagnostics exports. —
  backend: `services/api/test/integration/logSafety.integration.test.ts` captures the
  real pino output (a custom Fastify `logger.stream`, wired via a new test-only
  `AppDependencies.logStream` seam in `src/app.ts`) across `/me`, `/token/refresh`, and
  `/devices/:id` calls carrying a real `deviceCode`/`userCode`/PKCE verifier/access
  token/refresh token, and asserts none of those values appear anywhere in the captured
  text. **Finding**: Fastify's default request-log serializer only ever includes
  `method`/`url`/`host`/`remoteAddress` on the request and `statusCode` on the response —
  headers and bodies are never serialized into a log line at all, verified by printing
  the actual captured output during development. So the real protection right now is
  structural (nothing feeds secrets into the logger), not the `buildRedactPaths()` rules
  in `app.ts`, which currently redact paths (`req.headers.authorization`,
  `req.body.<forbidden field>`) that the default serializer never populates — those rules
  are correct defense-in-depth for if a future custom serializer or debug log call adds
  headers/body to the log record, not proof of current protection on their own. macOS
  diagnostics export doesn't handle device tokens (v1's diagnostics export predates
  Stage 5.2 and only covers local app state) — revisit if that export is extended to
  include auth state.

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

**Spike passed (2026-07-22).** `spikes/sqlcipher-feasibility/` — a deliberately isolated
SPM executable, not part of the main app target (GRDB v6, the app's current dependency,
and GRDB v7+SQLCipher both export a module literally named `GRDB`; they cannot coexist in
one target, so this spike proves feasibility before any production migration, exactly as
this gate is meant to gate).

- [x] Time-box an SPM + GRDB + SQLCipher build spike for Debug/Release, app bundling,
  hardened signing, architecture verification, and an empty encrypted DB open/read/write.
  — `swift build -c debug` (~9s cold) and `-c release` (~25s) both succeed.
  `spikes/sqlcipher-feasibility/Sources/SQLCipherFeasibilitySpike/main.swift` opens a real
  encrypted DB with a random 256-bit key (`SecRandomCopyBytes`, never derived from a
  password/token per this stage's own rule), writes a row, closes, reopens with the
  *same* key and confirms the row round-trips, then reopens with a *wrong* key and
  confirms it fails closed (`SQLite error 26: file is not a database` — GRDB's own
  internal schema-priming query trips on the undecryptable page immediately at open
  time, not just on first read, which is a stronger fail-closed property than the
  checklist strictly asked for). `PRAGMA cipher_version` confirms real SQLCipher 4.17.0
  community linkage rather than a silent plaintext fallback. All four checks pass
  identically in both Debug and Release. **Hardened signing found a real, fixable
  blocker**: ad-hoc `codesign --options runtime` alone breaks the build — dyld's library
  validation rejects loading `SQLCipher.framework` (a binary framework signed by Zetetic,
  a different Team ID than this ad-hoc-signed app) under hardened runtime. Fixed by
  signing with `--entitlements` carrying
  `com.apple.security.cs.disable-library-validation`; re-verified the signed, hardened
  binary still passes all four checks. **This means the real integration will need**:
  (a) `WriterFlow.entitlements` gains that key, and (b) `scripts/bundle.sh`'s release
  `codesign` call gains `--entitlements WriterFlow.entitlements` — which it currently
  lacks entirely (the entitlements file already exists in this repo but was never
  actually being applied at sign time, a pre-existing gap this spike surfaced, not
  something this spike changed). Architecture: arm64 only, matching this project's
  existing single-architecture ad-hoc DMG distribution — no universal-binary gap to
  chase.
- [x] Own and pin the required GRDB Swift-package fork/manifest, assign upstream and
  SQLCipher security-update responsibility, and prove SQLCipher is the only linked
  SQLite implementation for every advertised Release architecture. — vendored (not
  forked-on-GitHub, to avoid creating public content under the user's account without
  asking first) at `vendor/GRDB.swift/` — a pinned checkout of tag `v7.11.1` with the
  four-block SQLCipher patch already documented in GRDB's own `Package.swift` comments
  applied (uncomment the `SQLCipher.swift` dependency + `SQLITE_HAS_CODEC`/`SQLCipher`
  defines; delete the `GRDBSQLite` system-library target/product; enable the
  `GRDBSQLCipher` target). Re-applying this same four-block patch is how a future bump
  to a newer GRDB tag works — documented directly in the vendored `Package.swift`'s own
  comment. **Maintenance owner: not yet assigned** — whoever picks up the rest of Stage
  5.3 should also take upstream GRDB/SQLCipher security-update tracking, since vendoring
  means Dependabot-style automated update PRs won't fire for this dependency the way
  they might for a normal remote SPM package. `otool -L` on the Release binary confirms
  the only SQLite-family linkage is `@rpath/SQLCipher.framework/...` — no
  `/usr/lib/libsqlite3.dylib` (the system SQLite) anywhere in the link graph, so
  there's no dual-implementation ambiguity for the single arm64 architecture this
  project ships.
- [x] Confirm no conflicting system SQLite/SQLCipher symbols and include all required
  licenses/notices. — confirmed via `otool -L` above. Licenses: GRDB's MIT `LICENSE`
  file is present in the vendored checkout at `vendor/GRDB.swift/LICENSE`;
  `SQLCipher.swift` remains a normal remote SPM dependency (not vendored, just a
  `.package(url:...)` resolved at build time) carrying its own BSD-style license the
  same way every other remote SPM dependency in this project already does — no
  additional manual copying needed beyond what the existing GRDB v6/other dependencies
  already require.
- [x] Record binary size, startup/query cost, packaging impact, and maintenance owner.
  — Release binary: 5.2MB (spike-only executable; not representative of the full app's
  eventual size delta, since the main app links far more than this spike does — record
  a real delta once GRDB v7+SQLCipher actually replaces GRDB v6 in `Package.swift`, not
  before). Cold Release build: ~25s; incremental Debug rebuild: ~2s. Runtime cost of the
  four spike operations (open/write/close/reopen/read/reopen-wrong-key/fail): well under
  a second end to end, no perceptible startup delay from SQLCipher's key derivation at
  this data volume — a proper cost measurement against realistic history-table row
  counts is still open, deferred to the actual store refactor. Packaging impact:
  requires `SQLCipher.framework` to be embedded/signed inside the app bundle (a binary
  xcframework, not header-only) — `scripts/bundle.sh` doesn't do this yet; that's real
  work for the "Store refactor" section below, not this gate. **Maintenance owner: not
  yet assigned** (see above).
- [ ] If the spike fails, stop and approve a replacement ADR for CryptoKit AES-GCM field
  encryption and deliberately designed blind indexes before implementing persistence
  changes. Record its metadata/schema leakage and loss of general FTS/search explicitly.
  — **N/A, the spike passed.** Leaving unchecked rather than marking done-or-skipped,
  since "not applicable" and "done" mean different things for an Accept-criteria list a
  future reader might scan quickly.

### Store refactor

- [ ] Add a pre-store `LaunchCoordinator` that detects content-free binding/legacy state
  before constructing Dashboard view models or any account store. Refactor the current
  eager `AppDelegate → SettingsStore.shared → ConversionEventStore.shared →
  WriterFlowDatabase.shared` chain so it cannot open plaintext data before the migration
  lock.
  — **Partially done.** `Sources/WriterFlow/App/LaunchCoordinator.swift` exists with the
  full `opening`/`ready`/`locked`/`migrationRequired`/`recoveryRequired`/`failed` state
  enum and is wired to `WriterFlowDatabase.shared`'s open path — see the next item. What's
  NOT done yet: it doesn't run *before* the eager singleton chain (`SettingsStore.shared`,
  `ConversionEventStore.shared`, etc. are still touched ad hoc, first-access-wins, all over
  `AppDelegate`/`OverlayController`/`ActionEngine`/etc., not gated behind a single
  pre-store check), and `.locked`/`.migrationRequired` are unreachable — there's no
  encryption or migration yet for it to gate. Deliberately left as the harder remaining
  slice: fully centralizing that singleton chain is a wide-blast-radius change better done
  together with real encryption/migration than piecemeal ahead of it.
- [ ] Replace `WriterFlowDatabase.shared` with an injected account-scoped database owner
  that has explicit `opening`, `ready`, `locked`, `migrationRequired`, `recoveryRequired`,
  and `failed` states.
  — **State enum exists and is live** (`LaunchCoordinator.State`), and
  `WriterFlowDatabase.shared`'s open closure reports into it (`.ready` on success,
  `.failed(message)` on open/migration failure), surfaced as a red banner in
  `DashboardView`. Still `WriterFlowDatabase.shared` itself, not yet an injected,
  account-scoped owner — no encryption key, no per-account namespacing yet (next items).
- [x] Generate a random 256-bit local database key from system randomness and store it in
  a dedicated account-scoped `WhenUnlockedThisDeviceOnly` Keychain item.
  — `Sources/WriterFlow/Store/DatabaseKeychain.swift`, mirroring `DeviceTokenKeychain`'s
  pattern: `kSecClassGenericPassword`, no access group, `WhenUnlockedThisDeviceOnly` on
  write, `SecRandomCopyBytes` for the 256-bit key, `keyOrCreate(scope:)` so the same key is
  always reused rather than silently minted fresh and orphaning old data. Scope is an
  opaque caller-supplied string (meant to be the `(issuer, subject)` hash from the not-yet-
  built identity-binding item below); `nil`/empty scope maps to a distinct `"unscoped"`
  account for pre-sign-in/local-only use. **Not yet wired to actually key a database** —
  `WriterFlowDatabase` still opens a plain SQLite file; using this key requires the
  SQLCipher `usePassphrase` call plus the V1 atomic migration (below), intentionally kept
  as a separate, higher-risk step so encryption is never flipped on top of a user's real
  existing plaintext data without a migration path.
- [ ] Do not derive the DB key from password, OAuth token, refresh token, email, or network
  state.
  — Satisfied by construction in `DatabaseKeychain.generateKey()` (pure
  `SecRandomCopyBytes`), but leaving unchecked until the key is actually in use, since an
  unused generator proves nothing about the real code path.
- [x] Remove the production silent in-memory fallback on DB open/migration failure.
  — `WriterFlowDatabase.shared` still falls back to an in-memory `DatabaseQueue` so the app
  doesn't crash outright on a disk error, but it is no longer *silent*:
  `LaunchCoordinator.shared.state` flips to `.failed(message)` and `DashboardView` shows a
  red `StatusBanner` for the rest of the session. `swift build`/`swift test` both clean (76
  tests, 2 skipped, 0 failures) after this change.
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

- [x] In one transaction create `inference_requests`, a worst-case
  `quota_reservation`, and a pending `usage_ledger` attempt under unique
  `(user_id, idempotency_key)` before provider access.
  — `services/api/src/inference/accounting.ts`'s `reserveInferenceRequest`: one
  `withTenantContext` transaction inserts the `inference_requests` row and its
  `quota_reservations` row together; a matching `(user_id, idempotency_key)` short-circuits
  to the existing row instead of reserving twice. No `usage_ledger` row is written at
  reserve time — the schema only allows a `committed`/`reversed` `status`, so "pending" is
  represented by the reservation, not a ledger row; the ledger row is written atomically at
  commit (below), not as a separate pending-then-updated row.
- [x] Enforce the minimum request-state transitions and a free-alpha allowance so a
  duplicate or over-quota operation cannot reach Azure.
  — `OPERATION_STATE_TRANSITIONS` (`services/shared/src/operation.ts`, already existed from
  Stage 5.0) is enforced by `accounting.ts`'s `assertTransition` under a row lock
  (`SELECT ... FOR UPDATE`) on every `transitionState`/`commitInferenceRequest` call.
  `reserveInferenceRequest` checks the current `usage_balances` row (get-or-create per
  calendar month, `FREE_ALPHA_MONTHLY_UNITS` = 500) and throws `QuotaExceededError` before
  any row is inserted if the request would exceed it — proven by an integration test that
  pre-fills the balance to the cap and asserts zero `inference_requests` rows result.
- [x] On every success/failure/cancel/disconnect, commit provider usage/internal cost or
  release the reservation as applicable. Content never enters these rows.
  — `commitInferenceRequest` (success) and `releaseInferenceRequest` (failure/cancel) in
  `accounting.ts`; `routes/inference.ts` calls the latter from both its `catch` block and a
  `request.raw.on("close", ...)` listener, so a mid-stream client disconnect is handled the
  same as a server-side failure. Neither function ever takes request/output text as a
  parameter — only IDs and token counts.
- [x] Make the first Fix Grammar vertical slice prove one operation, one provider
  attempt, and one immutable ledger attempt before expanding action parity.
  — `POST /v2/inference/stream` (`services/api/src/routes/inference.ts`) implements exactly
  `requestedAction: "fixGrammar"`; every other action returns `VALIDATION_FAILED` with a
  message pointing at Stage 5.4 "Expand parity" as the reason, so this isn't a silent gap.
  The provider itself is `DevEchoProvider` (`services/api/src/inference/devEchoProvider.ts`)
  — a deterministic whitespace-collapsing stand-in, not real AI — because the real Azure
  OpenAI resource this would call is Stage 5.4's separate "Azure model plane" work, blocked
  on user cost approval. This lets the accounting/SSE/state-machine plumbing be proven end
  to end (reserve → running → streaming → completed, one ledger row, one balance debit)
  without spending money or shipping a fake "AI" correction to a real user; swapping in a
  real provider later only means a second class against the `InferenceProvider` interface,
  not touching the route or accounting code. `npm run check` (lint/typecheck/build/unit
  tests) passes; a new integration test
  (`services/api/test/integration/inferenceAccounting.integration.test.ts`) covers
  reserve→commit, idempotent replay, release-on-failure (including double-release being a
  no-op), and quota exhaustion — **not yet run against a real database**: Docker isn't
  reachable in this sandboxed session (same limitation noted for the website Docker build
  in Stage 5.2), so this is verified by lint/typecheck/build only, not by an actual DB run.
  Migration `012_alpha_pricing_version.cjs` seeds the flat placeholder pricing version
  `usage_ledger.pricing_version_id` requires — also unverified against a real database for
  the same reason.

### Azure model plane

- [ ] Provision at least one dev/staging Azure OpenAI resource/deployment reachable by
  private endpoint and private DNS only.
- [ ] Disable public network access and verify internet calls to the resource fail.
- [ ] Grant the Container App managed identity only the required inference role.
- [ ] Remove Azure API-key use from the WriterFlow backend path; if a temporary provider
  secret is unavoidable in dev, keep it in Key Vault and forbid it in app/artifacts.
- [ ] Add hard Azure budget, quota, and anomaly alerts.

### Server inference endpoint

- [x] Implement `/v2/inference/stream` for an explicit v1 action, beginning with Fix
  Grammar as the vertical slice.
  — `services/api/src/routes/inference.ts`. Registered in `app.ts` alongside the other
  route groups; `services/api/src/index.ts` wires the real (dev-stub) provider.
- [ ] Validate auth, device, entitlement, input schema/size, idempotency, concurrency, and
  quota reservation before provider access.
  — auth (`requireDeviceAuth`), device (checked device header must match the authenticated
  device), input schema/size (`InferenceRequestEnvelopeSchema.safeParse`, which carries the
  Stage 5.0 `maxLength`/`maxItems` caps), idempotency, and quota reservation are all done —
  in that order, before `provider.fixGrammar` is ever called. **Not done**: no per-user/org
  concurrency limit (nothing stops the same user opening N simultaneous streams today) and
  no entitlement/plan check beyond the flat free-alpha quota (there's only one plan right
  now, so there's nothing else to check yet — becomes real once Stage 5.5/Stripe exist).
- [ ] Compile prompts from server resources with behavior parity to current
  `PromptBuilder`/`Prompts`; record prompt version, not content.
  — Not done. `route`/`promptVersion` are hardcoded constants in `routes/inference.ts`
  matching `prompts/manifest.yaml`'s real `grammar@5.1.0` entry, but nothing actually reads
  `prompts/intents/grammar.md` or assembles a provider message from it — there's no real
  model call yet for a compiled prompt to go to (`DevEchoProvider` ignores it entirely).
  This is real work still ahead once the Azure model plane exists.
- [x] Stream typed SSE lifecycle events and provider text deltas.
  — exact canonical order from `Docs/contracts/inference-stream.md`:
  `request.accepted → decision → output.delta* → usage.summary → completed`, using the
  literal `InferenceStreamEvent` union from `@writerflow/shared` so a shape drift would be
  a compile error, not a runtime surprise.
- [ ] Configure APIM `forward-request buffer-response="false"`, no response cache, and no
  request/response body logging for SSE.
  — Infra work (`infra/apim`), not app code; not started this tick.
- [ ] Send keepalive events if an allowed operation could be idle near platform timeout.
  — Not implemented. Not yet meaningful against `DevEchoProvider`, which never blocks; real
  keepalive timing needs a real provider's actual latency profile to tune against.
- [x] Sanitize provider errors and never return upstream body/resource/deployment details.
  — the `catch` block in `routes/inference.ts` always sends a fixed
  `{code: "INTERNAL_ERROR", message: "Something went wrong. Please try again."}` regardless
  of the underlying error; the real error is only logged server-side
  (`request.log.error`, message only, matching the existing redact-path discipline).
  Trivially true today since `DevEchoProvider` has no "upstream" to leak — worth
  re-verifying once a real provider with real error bodies exists.
- [ ] Cancel provider work promptly when the client cancels/disconnects where the SDK and
  platform permit.
  — Partially done: `request.raw.on("close", ...)` releases the reservation immediately and
  the streaming `for await` loop checks a shared `lifecycle.terminated` flag and stops
  sending further deltas. **Not proven**: `DevEchoProvider` has no real cancellable
  in-flight work (its generator resolves near-instantly), so this path can't yet
  demonstrate an actual upstream provider call being aborted mid-flight — needs revisiting
  once a real provider with a genuinely abortable request exists.

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

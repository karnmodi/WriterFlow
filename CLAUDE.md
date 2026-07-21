# CLAUDE.md — WriterFlow

Context file for AI-assisted development. Read this first; it tells you what the project is, where the specs live, and how to work.

`CLAUDE.md` and `AGENTS.md` are intentional tool-specific mirrors. Update them together; their content should differ only where the filename/title itself is referenced.

## What this project is

WriterFlow is a native macOS menu bar app — an always-on, invisible writing assistant. When the user types in any app (Gmail, WhatsApp, Slack, anywhere), a small floating icon appears near the text field. Clicking it (or pressing `⌃⌥ Space`) opens an action popover: **Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt**. The app reads the field content and surrounding conversation via the macOS Accessibility API, sends it through the user’s Azure OpenAI resource (bring-your-own-key) only after explicit action, streams the result into a preview card, and replaces the text in place. Think "Whisperflow, but for typing instead of voice."

## Current state

**V1.0.0 is published** from tag `v1.0.0` at commit `7255390` (July 17,
2026). The shipped product is the completed Phase 0–4 native macOS app: AX focus/context
capture, non-activating overlay, action popover and prompt builder, streamed preview,
in-place/clipboard replacement, local GRDB history/memory/rules, Dashboard, resilience,
and the ARM64 ad-hoc-signed DMG. Its production AI transport is bring-your-own Azure
OpenAI endpoint/key/deployment configuration; the user's key is stored in that user's
Keychain and no publisher-owned/shared credential ships in the app.

**V2.0 Stage 5.0 is complete. Stage 5.1 (backend/database/infrastructure skeleton) is
code-complete and locally verified; its Accept criterion still needs a real cloud
deployment.** All Stage 5.0 checklist items are checked in
`phases/phase-5-v2-cloud-foundation.md`: ADRs 0001–0012, the v1 data inventory, the
per-cloud-table retention/deletion policy, the threat model, the OpenAPI/SSE/JSON-Schema
contracts, and the Stage 5.0 test fixtures all live under `Docs/` (`Docs/README.md` is
the index). For Stage 5.1: `services/api` (Fastify + health/ready endpoints),
`services/worker`, and `services/shared` (Zod contract schemas validated against the
Stage 5.0 fixtures) exist as one npm-workspaces TypeScript project — `npm run check`
passes. `services/api/migrations/001`–`008` (users/orgs/devices/inference/usage-ledger/
entitlements/outbox, RLS, append-only triggers, least-privilege roles) have been run
up→down→up against a real local Postgres container. `infra/bicep` (10 modules) and
`infra/apim` (JWT/pairing/SSE policies) are written and `az bicep build`/`lint`-clean.
Both service Dockerfiles build and the API image was smoke-run against local Postgres.
None of this has been applied to real Azure yet — the user has Azure/Entra CLI access
but no Entra External ID tenant created yet, and no `az deployment` has run — so Stage
5.1's Accept criterion (a live private-network deployment reachable through APIM) is
still open. The website's hosting model is now scoped and scaffolded (user decision,
2026-07-21): `website/` runs on Azure Container Apps in its own public environment,
separate from the API's internal-only one (`infra/bicep/modules/container-app-website.bicep`,
a second `container-apps-env.bicep` instantiation with `internal: false`, a matching new
subnet in `network.bicep`). It dropped `output: "export"` for `output: "standalone"` —
the three marketing pages are still statically prerendered at build time, unaffected in
content/behavior; only the new `/api/health` and `/pair` routes are dynamic. `/pair` is a
stub (reads the Mac app's `user_code`, doesn't sign anyone in yet — that needs the Entra
tenant plus an OIDC client library decision, a separate increment). `az bicep build`/lint
clean; `npm run check` passes; the standalone server was run and smoke-tested directly
(`node .next/standalone/server.js`). **Not verified**: the actual `docker build` — Docker
Hub image pulls hung indefinitely in this sandboxed session (reproduced with a plain
`docker pull alpine`, unrelated to this Dockerfile), so the container image itself is
unverified pending a real build environment.

**Stage 5.2 (real-user authentication) is in progress: the full WriterFlow-side pairing
and provisioning backend (ADR-0012 device tokens + a second web-session token issuer)
and the macOS `DeviceSessionProviding` client are built and verified — the Dashboard UI
and the Entra tenant itself are not started.** `services/api/src/jwt/` (ES256 signing, JWKS,
dev-only in-memory key — Key Vault-backed signing is cloud-apply-pending),
`services/api/src/pairing/{service,approve}.ts`, and migrations `009`–`011` implement
`POST /v2/device/authorize`, `POST /v2/device/token`, `POST /v2/token/refresh`, and
`POST /v2/device/approve` with PKCE, single-use device codes, poll rate-limiting,
rotating refresh tokens with reuse detection, and idempotent user/org/membership/device
provisioning — all proven end to end against a real local Postgres container as the
unprivileged `writerflow_app` role. Two real bugs were found this way and fixed, not
just discovered and left: migration 008's `devices` RLS policy failed closed for a bare
device-ID lookup (fixed with migration 010's session-flag-gated policy), and
`current_setting('app.tenant_id', true)` turned out to reset to an empty string rather
than `NULL` on a reused pooled connection, crashing every tenant policy's `::uuid` cast
(fixed with migration 008's `current_tenant_id()` SQL function). `/device/approve`'s
open design question — how the website authenticates its backend call to this API — is
resolved (user decision, 2026-07-19): a second WriterFlow-minted token audience
(`services/api/src/entra/verifier.ts` + `POST /v2/web-session/token`), wired to a real
Entra tenant's JWKS behind optional `ENTRA_*` config that's cloud-apply-pending.
`GET /v2/me` and `DELETE /v2/devices/:id` (`services/api/src/routes/account.ts`,
`src/account/service.ts`, `src/auth/guard.ts`) are also live: a shared
`requireDeviceAuth` guard re-verifies the bearer token and re-checks
`devices.revoked_at`/`users.status` live against Postgres on every call, device revoke
also kills that device's active refresh-token family, and ownership is scoped by
`user_id` so one user can never see or revoke another's device — all proven against real
Postgres (7 integration tests: happy path, missing/garbage token, cross-device revoke,
revoke-kills-refresh, cross-user 404, disabled-user 403). The previously-noted gap —
`pollDeviceToken`/`rotateRefreshToken` checking only `devices.revoked_at`, not
`users.status` — is now closed the same way. `Sources/WriterFlow/Store/{DeviceSession,DeviceSessionStore,
DeviceTokenKeychain,WriterFlowAPIClient,PKCE,MacHardwareModel}.swift` implement the Mac
side (URLSession + Keychain, no MSAL) — pairing state machine, poll/backoff, rotating
refresh, sign-out, cancellation, and the `writerflow://paired` foreground-hint deep
link — proven both by 21 new XCTest unit tests (real `swift test`, now that Xcode is
installed — see below) and by a live run against `services/api`'s real dev server on
real local Postgres. Two real bugs were found and fixed this way too: an early
`writerflow://paired` implementation deadlocked `swift test` for hours (a cancelled
`withCheckedContinuation` inside a `withTaskGroup` never actually resumed, and the group
waits for every child task), and the Keychain token item silently failed read-after-write
under `swift test`'s unsigned binary until a stray `kSecUseDataProtectionKeychain` was
removed to match the already-proven `KeychainStore` pattern. A production Sign-in/Account
UI now exists: a new Dashboard "Account" tab (`Sources/WriterFlow/Dashboard/{AccountView,
AccountViewModel}.swift`, `Sources/WriterFlow/Store/AccountService.swift`) covers sign-in
(shows the `user_code`, opens the browser), signed-in status (device label, plan, monthly
units, sync), sign-out, and a destructive device-revoke that always signs out locally even
if the server call fails — 13 new unit tests, compile+lint clean, but not visually
verified (no interactive display tooling in this environment to drive a native macOS UI).
It shows only the current device, not a device list — the API contract has no
list-devices endpoint. It's additive, not a replacement for v1's BYO-Azure onboarding
card (that swap needs a real cohort-flag mechanism that doesn't exist yet — Stage 5.4
territory — so replacing it now would risk breaking v1 users for no working alternative).
The `#if DEBUG` manual pairing menu item still exists for headless verification. The
Entra tenant itself (manual portal step, not yet done) is still outstanding. The active
v2 sources of truth are
`PRD-V2.md`, `V2-ARCHITECTURE.md`, `V2-ROADMAP.md`, and
`phases/phase-5-v2-cloud-foundation.md`. The explicit product-policy change for v2 is a
WriterFlow-operated authenticated backend: Entra External ID, encrypted local data,
PostgreSQL, a public authenticated edge with private Azure origin/model access,
server-authoritative usage/entitlements, Stripe-ready billing, contextual auto selection,
prompt enhancement, and server-side multi-model routing. Phase 5 changes transport and
identity first while preserving the v1 action UI; Phase 6 removes the normal options
flow only after classifier evaluation passes.

**V2 auth/distribution decision (2026-07-18, ADR-0010/0011/0012):** sign-in, membership,
and payment happen in the **web app** (the only Entra client, a confidential server-side
client). The Mac app is not an OAuth client; it obtains a WriterFlow-minted device token
through a browser device-authorization pairing flow (deep-link happy path + manual
`user_code` fallback) and calls `api.writerflow.app` with that token. V2 requires **no
Apple Developer account** and keeps v1's ad-hoc DMG + manual-Gatekeeper + manual-update
distribution. These supersede the earlier in-app MSAL PKCE (ADR-0002) and mandatory
Developer ID (ADR-0008) decisions.

Note: Xcode is now installed on this machine (as of Stage 5.2) — both `swift build` and
`swift test` work directly; `make test` runs the real XCTest suite, no CI/Xcode-only
dependency remains. (Historically this machine had only Command Line Tools, which is why
the sections below still describe the Package.swift-based build system rather than an
Xcode project — that deviation stands on its own merits and hasn't been revisited.)

### Build system deviation from original spec

The spec called for an Xcode project. Build system is **Swift Package Manager**
(`Package.swift`) with a bundle-wrapper script (`scripts/bundle.sh`) that produces
`build/WriterFlow.app`. Info.plist lives at the repo root (SPM disallows it as a
top-level resource). Everything else in the spec (AppKit + SwiftUI, `LSUIElement=YES`,
folder layout, min macOS 14) is honoured. `Package.swift` opens directly in Xcode if
preferred.

Common commands:

```
make build        # swift build
make test         # swift test
make lint         # swiftlint (brew install swiftlint first)
make bundle       # build + wrap as build/WriterFlow.app
make run          # bundle + open
```

## Source-of-truth documents

Read in this order before writing any code:

1. `PRD.md` — shipped v1 product requirements and historical baseline.
2. `PRD-V2.md` — active v2 product requirements and release criteria.
3. `ROADMAP.md` — master phase index and golden rules.
4. `V2-ARCHITECTURE.md` — v2 auth, API, encryption, database, Azure, Stripe, classifier, and prompt decisions.
5. `V2-ROADMAP.md` — v2 phase order, dependencies, and staged delivery path.
6. `RELEASE.md` — historical/canonical v1 packaging and security runbook.
7. `phases/phase-N-*.md` — the phase being implemented, with ordered task checklists and **Accept:** criteria. Phase 5 is next.

Never invent requirements — if something isn't specified in these docs, ask or propose in a comment before building.

## Tech stack (decided — do not change without discussion)

- **Language/UI:** Swift, AppKit + SwiftUI hybrid. Min target macOS 14. No Electron, no Tauri.
- **App type:** Menu bar only (`LSUIElement = YES`), no dock icon. Launch at login via `SMAppService`.
- **System integration:** Accessibility API (`AXUIElement*`), passive listen-only `CGEventTap` for typing detection, Carbon `RegisterEventHotKey` for the global hotkey.
- **Overlay:** non-activating `NSPanel` (`.nonactivatingPanel`, level `.floating`) — focus must NEVER leave the user's text field.
- **AI:** Production v1 is **bring-your-own-key**: the user configures their Azure OpenAI Responses endpoint, their API key (Keychain only), and deployment names. V2 deliberately replaces this with a WriterFlow authenticated SSE API; Azure credentials/deployments and prompt/model routing are server-side, with managed identity and private endpoints. No publisher-owned/shared reusable service credential may ship in any client.
- **Auth (v2):** browser-mediated. The web app is the confidential Entra External ID client and hosts membership/payment; the Mac app is not an OAuth client and pairs via a device-authorization flow to receive a WriterFlow-minted, per-device, revocable token (ADR-0011/0012). The Mac never holds an Entra token or client secret.
- **Storage:** V1 uses local SQLite via GRDB plus UserDefaults. V2 keeps GRDB but encrypts it with SQLCipher, moves user content out of UserDefaults, and adds private managed PostgreSQL for identity/membership/entitlement/usage state. Raw cloud inference content is ephemeral by default.
- **Backend (v2):** Microsoft Entra External ID · Azure API Management · TypeScript/Fastify on Azure Container Apps · Azure Database for PostgreSQL Flexible Server · Key Vault/App Configuration · Stripe. Do not substitute a different stack without updating the v2 ADR/specs.
- **Distribution:** V1 = public DMG containing an ad-hoc-signed app + SHA-256 + manual Gatekeeper approval/manual updates, with no Apple membership. **V2 keeps this same ad-hoc model — no Apple Developer account, no notarization, no Sparkle (ADR-0010)**, because browser-mediated auth removes the redirect-URI/Keychain-access-group dependencies that had required a Developer ID. NOT Mac App Store (private AX usage would be rejected).

## Project structure (create in Phase 0, keep to it)

```
WriterFlow/
├── App/            # entry point, menu bar, onboarding, settings plumbing
├── FocusMonitor/   # AXObserver, event tap, focused-field classification
├── Overlay/        # floating icon NSPanel, action popover, preview card
├── Engine/         # AI transport, prompt builder, action definitions
├── Store/          # GRDB models, Keychain, settings
├── Dashboard/      # SwiftUI dashboard window (history/memory/settings/usage)
├── Adapters/       # per-app compatibility (Chrome, Electron, Safari…) — Phase 2
├── services/       # v2 API, worker, shared schemas
├── infra/          # v2 Bicep and API Management policy
├── prompts/        # v2 versioned server prompt resources and evals
├── phases/         # planning docs (this repo's specs)
├── PRD.md · PRD-V2.md · ROADMAP.md · V2-*.md · RELEASE.md · CLAUDE.md
```

## Golden rules (non-negotiable)

1. **Focus:** no window we show may ever steal keyboard focus from the user's text field. Test caret-keeps-blinking after every UI change.
2. **Privacy:** in production, text is sent to the selected AI processing service ONLY on explicit user action. The event tap is listen-only, used solely as an "is typing" timestamp — never buffer or log key contents. V1 classification begins after the action menu opens; v2 auto selection/classification may begin only after the user clicks the icon or presses the explicit hotkey.
3. **Secure fields:** role `AXSecureTextField` or `IsSecureEventInputEnabled()` → WriterFlow is completely inert. No icon, no reads.
4. **Main thread:** all AX calls and network calls off-main, AX calls wrapped with a 500 ms timeout (AX can hang on busy apps).
5. **Secrets:** no publisher-owned/shared reusable service credential may be embedded, bundled, downloaded, copied to Application Support, persisted in Keychain/UserDefaults, or logged by a production client. Development credentials stay local and never enter a public artifact. Any provider-issued device token needs an explicitly supported public-client lifecycle and security review.
6. **Performance:** idle CPU < 1%, icon appears < 150 ms after first keystroke, first streamed token < 800 ms target.
7. **Graceful degradation:** AX read/write fails → clipboard fallback (Phase 4) or a clear error — never a hang or silent no-op.

## Coding conventions

- Swift Concurrency (`async/await`, actors) over GCD where possible; `@MainActor` explicitly for UI.
- One responsibility per type; components communicate via small protocols (e.g. `FocusMonitorDelegate`) so they're testable without AX.
- Prompts live in editable resource files, not inline strings.
- `os_log` with categories: `focus`, `overlay`, `engine`, `store`. No print().
- Unit tests for prompt building, diffing, store; AX behavior is verified manually per the **Accept:** criteria (list of target apps in each phase file).
- Commit per stage, message format: `phase0.3: FocusMonitor AXObserver + typing signal`.

## Known platform gotchas (learned in research — respect these)

- Chrome only exposes web content after setting `AXEnhancedUserInterface = true` on its AX app element.
- Electron apps (Slack, WhatsApp Desktop, Notion) need `AXManualAccessibility = true`.
- CGEventTaps get disabled by the OS under load — listen for `kCGEventTapDisabled(ByTimeout|ByUserInput)` and re-enable.
- AXObserver must be re-attached on every app activation (`NSWorkspace.didActivateApplicationNotification`); test rapid ⌘Tab.
- Setting full `kAXValue` destroys rich-text formatting — prefer `kAXSelectedTextRange` + `kAXSelectedText` replacement.
- AI providers retire models quickly — production routing belongs on the provider platform once selected. A client may consume only a validated static, non-secret fallback config; never credentials or an arbitrary service contract.

## How to work a phase

1. Open `phases/phase-N-*.md`, read the whole file.
2. Implement stage by stage, in order. Don't start stage N+1 with stage N's Accept criteria failing.
3. Tick checkboxes in the phase file as tasks complete; note deviations inline under the task.
4. At phase end, verify the exit criteria + ROADMAP's definition of done (no regressions, CPU/memory budget).
5. Update the "Current state" section of this file to point at the next phase.

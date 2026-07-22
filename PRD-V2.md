# WriterFlow v2.0 — Product Requirements Document

**Status:** Planned  
**Date:** July 17, 2026  
**Baseline:** WriterFlow v1.0.0 (`7255390`)  
**Owner:** Karan

WriterFlow v2 turns the published, bring-your-own-Azure-key macOS app into an
account-backed service. The native Accessibility and overlay experience stays local;
authentication, entitlement checks, prompt orchestration, model routing, and metered
usage move behind a WriterFlow-operated cloud boundary.

This PRD is the product source of truth for v2. Technical decisions and API/data
contracts live in [`V2-ARCHITECTURE.md`](V2-ARCHITECTURE.md). Delivery order lives in
[`V2-ROADMAP.md`](V2-ROADMAP.md), beginning with
[`phases/phase-5-v2-cloud-foundation.md`](phases/phase-5-v2-cloud-foundation.md).

---

## 1. Product decision

V2 explicitly reverses v1's “no custom WriterFlow API” constraint.

- V1 remains a local-first BYO Azure product and historical release baseline.
- V2 uses a WriterFlow account and a WriterFlow-operated, authenticated API.
- Sign-in, membership, and payment happen in the **web browser**. The Mac app is not
  an OAuth client; after a browser-completed sign-in (and membership, when upgrading)
  the app pairs to that session and receives a WriterFlow-minted device token
  (ADR-0011, ADR-0012).
- V2 does **not** require an Apple Developer account. The app continues v1's ad-hoc
  distribution (DMG + SHA-256 + manual Gatekeeper approval + manual updates); there is
  no notarization or auto-update mechanism (ADR-0010).
- The Mac app never receives a WriterFlow-owned Azure credential, Azure deployment
  name, Stripe secret, database credential, Entra token, or backend service
  credential. Its only credential is a per-device, revocable WriterFlow token.
- The app-facing edge is internet reachable because a consumer desktop app must reach
  it. It is not anonymous: every inference request requires a valid user token,
  entitlement, quota, idempotency key, and server-side authorization.
- The backend, database, model plane, prompt assets, and provider credentials are not
  publicly reachable. Azure OpenAI is accessed only from WriterFlow infrastructure.
- Text and surrounding context still leave the Mac only after a click or hotkey. Auto
  selection changes what happens after that explicit trigger; it never authorizes
  passive cloud inference.

## 2. Problem

V1 proves the native interaction but puts production setup and provider billing on each
user. It also exposes action selection as a menu even when app, window, field, thread,
and user preference signals often make the desired operation predictable.

V2 must solve four connected problems:

1. Give real users a durable identity and secure device session without embedding a
   client secret in the Mac app.
2. fund and protect shared cloud inference without exposing provider access or trusting
   client-reported membership and usage;
3. encrypt local and cloud user data while retaining WriterFlow's local-first privacy
   posture; and
4. reduce the core interaction to explicit trigger → contextual result → Replace,
   using automatic intent and model selection instead of a pre-generation options menu.

## 3. Goals

### 3.1 Release goals

- Browser-delegated sign-up/sign-in for real users, with account and device session
  management in the Dashboard.
- An authenticated, abuse-resistant streaming API whose origin services and Azure
  resources have no public ingress.
- App-level encryption for local WriterFlow content and envelope encryption for any
  sensitive cloud-persisted personalization.
- Server-side logical routing across multiple Azure model deployments and regions.
- Server-authoritative memberships, entitlements, quotas, usage ledger, and cost data.
- Stripe Checkout, Billing, Entitlements, and Customer Portal integration without card
  handling in WriterFlow.
- Contextual auto selection that removes the normal action-options step.
- A versioned prompt-enhancement pipeline and measurable quality evaluation set.
- Personalized routing and writing behavior derived from accepted results and explicit
  feedback, with clear local/cloud controls.
- A safe migration for existing v1 local history, memory, rules, settings, and BYO
  credentials.

### 3.2 Experience goals

- Normal flow: type → click the icon or press the hotkey → preview streams immediately
  with a small intent label → Replace/Copy/Retry/Discard.
- No action menu before a normal generation.
- WriterFlow identifies reply, grammar repair, tone rewrite, elaboration, custom
  instruction, or prompt enhancement from field text, selection, app/site, window,
  visible thread, and user preferences.
- A wrong decision is recoverable from the preview through a secondary “Change intent”
  control; WriterFlow never replaces text without confirmation.
- Shift-clicking the icon or pressing `⌃⌥⇧ Space` opens the existing non-activating
  Custom-instruction composer directly, without first spending an auto-generation call.
  Normal click/`⌃⌥ Space` remains auto write.
- The user sees a plain-language usage allowance and membership state, not provider
  deployment names or raw Azure pricing configuration.

## 4. Non-goals

- Voice dictation or speech recognition.
- Windows/Linux support.
- A public developer API, API keys for third-party callers, or user-created model
  endpoints.
- On-premises deployment, customer VPC deployment, SCIM, SAML enterprise SSO, or team
  administration in the first v2 release. The data model must leave room for them.
- End-to-end encryption of text being processed by a cloud model. The backend and model
  provider must see request plaintext during inference; WriterFlow must say this
  directly.
- Uploading the user's full local conversion history by default.
- Charging by model tokens directly in the UI. Tokens are implementation data; customer
  pricing uses plan allowances and stable billable units.
- Fully autonomous replacement or sending. Preview and explicit Replace remain required.
- Building a custom password database or password-reset system.

## 5. Target users and account model

### 5.1 Initial users

- Individual macOS users who want setup without an Azure subscription.
- Existing v1 users upgrading with local history and personalization already present.
- Early paid users whose usage and quality needs exceed the free allowance.

### 5.2 Account and organization shape

- Every person has one `user` identified by the immutable identity-provider issuer and
  subject, never by mutable email.
- Every new user receives a personal `organization` and an owner `membership` even
  though v2.0 exposes only an individual UI. This prevents a later team migration from
  rewriting ownership on every record.
- A user can register multiple devices. Devices can be listed and revoked.
- Account suspension, membership, entitlement, and quota are separate states.
- One active signed-in WriterFlow account per local macOS profile is supported at v2.0.
  The first account is explicitly bound to that macOS profile. A different identity is
  blocked unless the user exports as needed and deliberately removes the existing local
  WriterFlow account data; account switching is deferred, but storage is namespaced so
  it can be added safely.

## 6. Core user journeys

### 6.1 Upgrade from v1

1. WriterFlow updates without modifying the v1 database or deleting the BYO key.
2. The Dashboard explains the cloud-processing change and opens browser sign-in.
3. After successful sign-in, WriterFlow creates an encrypted account-scoped local store
   bound to that first immutable identity and atomically migrates existing history,
   memory, rules, and voice profile exactly once.
4. The user performs a cloud-transport test action.
5. Only after that succeeds may WriterFlow offer to remove the old Azure key. It never
   silently deletes the key or makes two provider calls for one action.
6. A time-limited beta rollback can restore the v1 transport; it is removed before v2 GA.

The legacy global store is never copied into a second identity. Before the first binding,
v2 detects it without eagerly opening content stores; after migration, the last-bound
encrypted store remains locally readable offline or signed out.

### 6.2 Sign in on a new Mac (browser pairing)

1. The user grants Accessibility and Input Monitoring as today.
2. The user selects **Sign in**. WriterFlow requests a pairing
   (`POST /v2/device/authorize`) and shows a short `user_code`, then offers to open
   the browser (happy path: a deep link / `verification_uri_complete`) with a manual
   `writerflow.aviusolutions.com/pair` code-entry fallback.
3. In the browser, the web app completes Entra sign-in (and membership, if upgrading),
   confirms the device, and approves the pairing under its authenticated session.
   `/v2/bootstrap`-equivalent provisioning of the user, personal organization,
   membership, and device happens on the web/backend side during this step.
4. WriterFlow polls `POST /v2/device/token` and receives WriterFlow-minted access and
   refresh tokens, stored in its own Keychain item. No password, Entra token, or app
   client secret is handled by the Mac app.
5. WriterFlow then fetches account, entitlement, privacy, and usage state from
   `/v2/me` using its device token.

### 6.3 Automatic writing action

1. Passive typing only updates local icon state.
2. The user clicks the icon or presses the hotkey. That is the explicit authorization
   boundary for field/context capture and one cloud operation.
3. WriterFlow re-reads and fingerprints the focused target, captures only the allowed
   field/selection/context, and sends structured context signals.
4. The backend validates identity, device, membership, entitlement, quota, request size,
   and idempotency.
5. The orchestrator chooses intent, prompt pipeline, and logical model route. Obvious
   cases use deterministic routing; ambiguous cases use a low-cost classifier.
6. The first stream event identifies the chosen intent and confidence; text deltas follow.
7. The preview remains non-activating. Replace performs the existing focus/refocus guard
   and only records acceptance after the write succeeds.

### 6.4 Billing

1. The Dashboard shows the current plan, allowance, current-period usage, and hard cap.
2. Upgrade opens a backend-created Stripe Checkout Session in the browser.
3. Stripe webhooks update WriterFlow's entitlement projection asynchronously.
4. The Mac app refreshes `/v2/me`; it never trusts Checkout redirect parameters as
   proof of payment.
5. Manage Billing opens a short-lived Stripe Customer Portal Session.

## 7. Functional requirements

### 7.1 Authentication and sessions

- Use a managed customer identity provider. The v2 recommendation is Microsoft Entra
  External ID, integrated **in the web app** through browser-delegated OAuth/OIDC + PKCE
  as a confidential client.
- Initial sign-in methods: email one-time passcode plus one social provider. Apple,
  Google, Microsoft, MFA, and enterprise federation may be enabled as product needs
  justify, without changing WriterFlow's internal user key.
- Email OTP's short (~24h) refresh lifetime is a web-session concern; because the Mac
  holds a WriterFlow-minted refresh token rather than an Entra token, daily Entra
  reauthentication does not force daily device re-pairing. Still disclose reauth copy
  plainly and prefer a persistent social provider in the web flow.
- The Mac app is **not** an OAuth client, embeds no client secret and no Entra client
  ID, and pairs to a browser-completed session via a device-authorization flow
  (ADR-0011).
- Store only the WriterFlow-minted device token in the app's own Keychain item
  (no shared access group). Never persist it in UserDefaults, Application Support,
  diagnostics, or logs. Token loss is recoverable by re-pairing and never affects the
  local database key.
- The API edge validates **WriterFlow-issued** device tokens (issuer, audience,
  signature, expiry, scope); the web app validates Entra tokens server-side. The
  application authorization layer re-checks user/membership/device/entitlement.
- Support sign-out, device list/revocation, global account disable, and account deletion.
  Revocation invalidates the device's rotating refresh-token family.
- A network outage must not make the encrypted local database unreadable. Authentication
  controls cloud operations, not local key availability.

### 7.2 WriterFlow API

- Provide a versioned HTTPS API at `apiwriterflow.aviusolutions.com`.
- Provide device-pairing endpoints (`/v2/device/authorize`, `/v2/device/token`) and a
  refresh endpoint; these mint/rotate WriterFlow device tokens (ADR-0012). Pairing
  endpoints are unauthenticated but rate-limited and PKCE-bound; every other route
  requires a WriterFlow bearer token.
- The app-facing contract is capability based: Phase 5 sends existing actions through
  inference `mode=explicit`; Phase 6 uses `mode=auto`; separate capabilities cover
  `style_analyze`, account state, personalization sync, and billing sessions.
- Require `Authorization: Bearer`, a unique operation/idempotency key, client version,
  and registered device identifier on inference requests.
- Stream inference through typed SSE events: accepted, decision, output delta, usage
  summary, completed, and sanitized error.
- Disable Replace/Copy until completed. Broken streams never silently retry or apply
  partial output; failed/cancelled requests record internal provider cost but consume no
  customer billable units, while an explicit Retry is a new operation.
- Never forward provider error bodies, deployment names, resource hosts, or secrets.
- Limit request bytes, text/context lengths, concurrency, calls per minute, tokens per
  period, and account spend before provider work starts.
- Stripe's event endpoint is isolated from user APIs and authenticates the raw request
  with Stripe's webhook signature, not a WriterFlow user token.

### 7.3 Encryption and data handling

- Keep GRDB as the Mac persistence API but run it on an encrypted SQLCipher database.
- Generate a random local database key and store it in Keychain separately from auth
  tokens. Move voice profile and recent custom instructions out of plaintext
  UserDefaults into the encrypted database.
- Provide an atomic plaintext-to-encrypted database migration with backup, verification,
  rollback, and a visible recovery state. A key/open failure must never silently fall
  back to an empty in-memory database.
- Use managed PostgreSQL as the cloud source of truth. Platform encryption at rest and
  TLS are mandatory; sensitive synced content additionally uses per-user envelope
  encryption with versioned wrapped data keys.
- Raw field text, surrounding context, prompts, and model output are transient within
  WriterFlow by default and excluded from gateway/application/analytics logs and cloud
  content tables. Azure/model-provider handling and retention still follow the
  separately disclosed provider contract and resource configuration.
- Persist usage metadata, route class, token counts, latency, status, and opaque request
  IDs without inference content.
- Cloud personalization sync is opt-in. Raw conversion-history sync is deferred.
- Support export, retention, and deletion workflows. Live encrypted content/wrapped-key
  deletion is immediate, but irreversible backup deletion completes only after the
  disclosed PostgreSQL backup-retention window; restoration must reapply deletion
  tombstones before serving traffic.

### 7.4 Contextual classifier and no-options flow

- Replace `RecommendationEngine`'s “highlight an action row” behavior with an
  `AutoActionCoordinator` that owns one explicit-trigger operation.
- Extend field identity beyond PID/bundle/role to include window/site, element identity
  where available, field frame, and a content/selection revision fingerprint.
- Classifier inputs include only request-time data: app bundle, resolved site, window
  category, selection state, field length/shape, conversation presence, draft/context,
  and enabled personalized preferences.
- Intent taxonomy: reply, grammar repair, tone rewrite, elaborate, custom transform,
  prompt enhancement, and neutral improve.
- Deterministic rules handle high-confidence cases first. A cloud classifier is used only
  when needed and returns a structured decision with confidence and reason code.
- Low confidence defaults to neutral improve; it must not silently choose a destructive
  insert/replace mode.
- The default pre-generation options panel is removed. A secondary correction control
  remains in preview and feeds explicit feedback to the classifier evaluation set.
- Preserve deliberate free-text Custom work through Shift-click or `⌃⌥⇧ Space`, which
  opens Custom entry directly. Do not auto-generate and then ask for the instruction.

### 7.5 Prompt enhancement

- Move prompt policy from inline client strings to versioned backend resource files with
  a manifest, prompt version, and regression evals.
- Build a typed `PromptPlan` from intent, app/site, context, personalization, output mode,
  constraints, and model capability.
- Keep server policy/task controls, explicit user instructions, personalization, and
  quoted untrusted field/conversation data in distinct trust classes. No text supplied
  by the Mac may select an arbitrary tool, URL, deployment, template, entitlement, or
  insert/replace behavior outside validated enums.
- Normal grammar/tone/reply operations use deterministic prompt assembly; do not spend a
  second model call merely to rewrite the instruction.
- Prompt-oriented destinations such as ChatGPT, Claude, Gemini, Cursor, and Copilot use a
  dedicated prompt-enhancement route whose result is the send-ready enhanced prompt.
- Ambiguous complex custom instructions may use a lightweight enhancer before generation
  only when an evaluation shows enough quality gain to justify latency and cost.
- Record prompt version and logical route in usage telemetry, never the prompt content.

### 7.6 Personalization

- Preserve v1 voice profile, facts, snippets, and per-app rules.
- Keep detailed samples and conversion history encrypted and local by default.
- Send only enabled profile/rule material required for the explicit request.
- Store a small, editable derived style profile in the cloud only when sync is enabled.
- Personalization learning comes from successful Replace/Copy outcomes, explicit intent
  corrections, and the existing user-triggered style analysis. It never uploads accepted
  outputs in the background without a disclosed opt-in.
- Classifier preferences are scoped by app/site category and decay or can be reset.
- Users can inspect, edit, disable, export, and delete learned information.

### 7.7 Azure multi-model routing

- Azure resource endpoints and deployment names exist only in server configuration.
- Logical routes: classifier, grammar, standard rewrite, premium rewrite, prompt
  enhancer, and style analyzer.
- A route maps to one or more Azure deployment targets with region, priority, health,
  timeout, model capability, and cost metadata.
- Routing considers intent, complexity, latency target, context size, entitlement,
  remaining allowance, deployment health, and explicit quality retry.
- Use managed identity/RBAC from the backend to Azure OpenAI wherever supported.
- Disable public network access to Azure OpenAI and reach it through a private endpoint.
- Circuit breaking and fallback must not make two successful billable model calls for one
  logical stage. Every provider call is metered, including classifier and enhancer calls.
- Model changes are deployed through server configuration and evals; no Mac app update is
  required.

### 7.8 Memberships, usage, and Stripe

- Separate identity, organization membership, product entitlement, quota, and billing
  records.
- WriterFlow's database is the low-latency entitlement projection. Stripe is the source
  of truth for payment/subscription events; the inference path never calls Stripe.
- Create Stripe Customer, Checkout Session, and Customer Portal Session only on the
  backend.
- Verify webhook signatures from the raw body, deduplicate event IDs, tolerate retries
  and out-of-order delivery, and reconcile periodically with Stripe.
- Maintain an append-only usage ledger with provider-reported token counts, internal cost
  in micros, stable billable units, pricing version, request stage, and idempotency key.
- Launch pricing shape:
  - **Free:** account, encrypted local data, standard auto writing, monthly allowance.
  - **Pro:** larger included allowance, premium route access, longer context, advanced
    personalization, and priority processing where configured.
  - **Team/Business later:** seat membership, shared policies, admin roles, SSO/SCIM,
    centralized billing, and retention controls.
  - **Metered overage later:** explicit opt-in, hard spend cap, alerts, and Stripe meter
    events generated from WriterFlow's reconciled usage ledger.
- Do not set final currency prices or allowance sizes until shadow metering measures real
  classifier + enhancer + generation cost and latency on representative usage.

## 8. Recommended data boundary

| Data | Mac | WriterFlow cloud | AI provider |
|---|---|---|---|
| Auth tokens | WriterFlow device token in Keychain only; no Entra token on device | Entra validated web-side; WriterFlow token issuance/validation metadata | No |
| Local history input/output | Encrypted, default 90-day retention | No by default | Request-time use plus disclosed provider retention/configuration |
| Voice profile/rules | Encrypted | Optional encrypted sync | Enabled request-time subset plus disclosed provider retention/configuration |
| Field/context/output | In memory + encrypted local event after outcome | Transient in WriterFlow, no content logs | Request-time processing under disclosed provider contract/configuration |
| Identity/membership | Cached minimal display state | PostgreSQL source of truth | No |
| Usage/billing | Display cache | Append-only ledger + Stripe IDs | Provider usage response only |
| Model routing/prompts | Logical labels only | Versioned config/resources | Compiled request |

## 9. Success metrics and service objectives

### 9.1 Product

- At least 85% exact-intent accuracy and 95% acceptable-route accuracy on a labeled
  cross-app evaluation set before removing the action panel for all users.
- At least 70% preview acceptance among retained weekly users.
- Fewer than 5% of operations use “Change intent” after the classifier warm-up period.
- Sign-in-to-first-rewrite under 2 minutes on a clean supported Mac with permissions
  already granted.

### 9.2 Performance

- App/icon response to typing remains under 150 ms because it stays local.
- WriterFlow edge/orchestrator overhead, excluding model time, p95 under 250 ms in the
  primary region.
- First output delta p50 under 1.0 s and p95 under 2.0 s for deterministic standard
  routes on the defined UK/US test matrix.
- Ambiguous classifier + generation first delta p95 under 2.5 s.
- No main-thread AX or network calls; no regression from v1 replacement behavior.

### 9.3 Reliability and security

- 99.9% monthly availability target for authenticated inference after GA.
- No provider/shared credential in the app, DMG, logs, or client configuration.
- No public ingress to the backend origin, PostgreSQL, Key Vault, or Azure OpenAI.
- Cross-tenant authorization tests prove one organization cannot read or mutate another.
- 100% of provider calls map to exactly one usage-ledger stage record; no duplicate Stripe
  meter events for the same ledger record.
- Local plaintext-to-encrypted migration passes forced interruption, wrong-key, disk-full,
  rollback, and backup-recovery tests.

## 10. Release approach

### 10.1 Private alpha

- Cloud infrastructure and auth exist, but v1 transport remains behind a developer-only
  rollback flag.
- Inference relay preserves the current explicit action menu so transport can be tested
  independently from auto-selection UX.
- Usage and hypothetical billing run in shadow mode; no charge is created.

### 10.2 Beta

- Auto selection is enabled for a cohort, with preview correction and classifier telemetry.
- Local encryption migration is mandatory and recovery tested.
- Free allowance is enforced; Pro can be enabled through Stripe test/live mode after
  webhook reconciliation passes.
- BYO Azure UI becomes a migration-only advanced path and makes no parallel calls.

### 10.3 General availability

- Normal options flow removed.
- WriterFlow backend is the only production inference transport.
- Pricing, allowances, privacy/retention copy, subprocessor disclosure, support path, and
  account deletion are public and tested.
- Provider resource, database, and origin public-network access are verified disabled.
- Distribution follows the v1 ad-hoc model (DMG + SHA-256 + documented manual Gatekeeper
  approval + manual updates); no Apple Developer account, notarization, or auto-update is
  required (ADR-0010). Install/update friction is disclosed on the install page.

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A desktop API cannot be truly secret/private | Public authenticated edge; private origins/model plane; no security-by-obscurity claims |
| Account system adds friction to v1 | Browser SSO/OTP, preserve local data, test transport before removing BYO key |
| Wrong auto action | Strong target identity, deterministic high-confidence rules, typed confidence, preview-only output, secondary correction |
| Classifier doubles latency/cost | Skip it for obvious cases, fuse orchestration behind one client request, meter every stage, cache only safe decisions |
| Encryption migration appears to lose data | Atomic export/verify/swap, backup/rollback, remove silent in-memory fallback |
| Stripe event delay or duplication | Internal entitlement projection, verified/idempotent webhook inbox, reconciliation job, grace policy |
| Model retirement or regional quota | Logical routes, multiple deployment targets, health/circuit breaker, server-side config and evals |
| Cloud personalization creates privacy surprise | Local by default, explicit sync control, request-time minimization, export/delete, precise retention copy |
| Cost exceeds subscription revenue | Preflight quota reservation, hard account/org spend ceilings, shadow pricing, route by entitlement and cost |

## 12. Decisions deliberately left until measured

- Exact Free and Pro prices, included units, trial length, and overage price.
- Whether Pro launches at v2.0 GA or shortly after the free authenticated service.
- Which social identity providers ship beyond email OTP.
- Whether cloud personalization sync is GA or beta.
- Whether prompt enhancement ever uses a second provider call outside complex custom work.
- The threshold for adding Redis, a queue service, a second region, or a dedicated worker;
  PostgreSQL plus an outbox is the initial path.

These are commercial or scale decisions, not reasons to defer the foundational schema,
usage ledger, entitlement checks, encryption, or route abstraction.

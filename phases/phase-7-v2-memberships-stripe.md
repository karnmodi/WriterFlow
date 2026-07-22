# Phase 7 — Memberships, usage pricing, and Stripe

**Goal:** Free and Pro access is server-authoritative and self-service. The system can
support teams and metered overage later without rebuilding identity or the ledger.

**Inputs:** [`PRD-V2.md`](../PRD-V2.md),
[`V2-ARCHITECTURE.md`](../V2-ARCHITECTURE.md), and
[`V2-ROADMAP.md`](../V2-ROADMAP.md).

## Phase-wide non-negotiables

- Entitlement and quota checks read PostgreSQL only — no Stripe call in the inference hot path.
- Stripe secret keys and webhook secrets are backend-only; never ship in the Mac app or website bundle.
- Checkout success URLs are UX only; access changes only after verified webhook projection.
- One personal organization maps to one Stripe customer; never join billing to login by email.
- Webhook handlers verify signatures against the raw body, durably inbox events by Stripe event ID,
  and process projection work asynchronously.
- Do not tie plan promises to specific Azure model slugs — use feature/limit keys from
  `V2-ARCHITECTURE.md` §9.3.

## Stage 7.1 — Entitlement and allowance engine

- [x] Migration `013_billing.cjs` — `billing_customers`, `subscriptions`, `stripe_events` tables
  with tenant RLS on org-scoped billing tables (`V2-ARCHITECTURE.md` §8.2).
- [x] `services/api/src/entitlements/engine.ts` — evaluate plan/features from
  `entitlement_projection` + normalized subscription state, including past_due grace behavior.
- [ ] Wire `readEvaluatedEntitlement` into `/me`, inference authorization, and quota enforcement.
- [ ] Define feature/limit keys independent of model names in shared contract schemas.
- [ ] Project grants from trial, plan, support/promo, admin, and Stripe sources into
  `entitlement_projection`.
- [ ] Enforce monthly units, context limits, route access, concurrency, and hard spend caps.
- [ ] Document and test grace behavior for transient billing/event delays.

**Accept:** changing an entitlement affects the next request without an app update or
Stripe call in the request path.

## Stage 7.2 — Stripe subscription foundation

- [x] `services/api/src/billing/stripe.ts` — backend-only Stripe client wrapper
  (`STRIPE_SECRET_KEY` optional at boot).
- [x] `services/api/src/routes/billing.ts` — route registration with Checkout/Portal stubs
  (501 until configured / implemented) and `POST /webhooks/stripe` idempotent inbox skeleton.
- [x] Wire billing routes in `services/api/src/app.ts`.
- [x] Unit tests for entitlement engine, Stripe wrapper, and billing routes.
- [ ] Backend-only Stripe Customer create/lookup mapped to `billing_customers`.
- [ ] Product/Price lookup-key mapping for Checkout Session creation.
- [ ] Implement `POST /billing/checkout-session` and `POST /billing/portal-session`.
- [ ] Worker/async processor for `stripe_events` inbox → subscription snapshot + entitlement grants +
  outbox.
- [ ] Scheduled reconciliation against canonical current Stripe objects.
- [ ] Stripe Entitlements → coarse feature projection persistence.
- [ ] Integration tests: upgrade, renewal, payment failure, downgrade, cancellation, reactivation,
  duplicate webhook, and reordered webhook delivery.

**Accept:** test-mode upgrade, renewal, payment failure, downgrade, cancellation, and
reactivation produce the correct WriterFlow entitlement after duplicate and reordered
webhook tests.

## Stage 7.3 — Free and Pro product surfaces

- [ ] Replace Azure endpoint/key/deployment Settings with Account, Plan, Usage, Devices, and
  Privacy cards.
- [ ] Show included/remaining WriterFlow units and reset date; keep local acceptance/usage
  analytics clearly separate.
- [ ] Add upgrade and manage-billing browser flows on `website/`.
- [ ] Add upgrade and manage-billing entry points in the Mac Dashboard Account tab.
- [ ] Do not expose provider tokens, raw costs, or deployment configuration as customer
  pricing.

**Accept:** a user can understand current access, upgrade, manage billing, and recover
from a failed payment without support intervention.

## Stage 7.4 — Personalization sync (optional v2 GA candidate)

- [ ] Per-user envelope key and encrypted derived profile/rules.
- [ ] Explicit sync toggle, last-sync state, conflict policy, export, live deletion, restore
  tombstones, and disclosed backup-expiry behavior.
- [ ] Never sync raw history by default and never conflate sync with product-training consent.

**Accept:** two Macs signed into the same user converge on enabled profile/rules; disabling
sync prevents future cloud writes; deletion removes live wrapped keys/content; and a
backup restore cannot resurrect a tombstoned user before final backup expiry.

## Stage 7.5 — Metered overage readiness

- [ ] Run billable-unit computation and Stripe meter outbox in shadow mode.
- [ ] Reconcile ledger totals, provider invoices, plan revenue, retries, refunds, and failed
  requests for at least one full billing cycle.
- [ ] Add explicit opt-in, price disclosure, hard spend cap, usage alerts, and support/refund
  policy before charging overage.

**Accept:** 100% ledger-to-meter identifier reconciliation with no duplicates. Charging
remains off until the commercial decision is approved.

## Phase 7 exit

- Server-authoritative Free/Pro entitlements with no Stripe round trip on inference.
- Self-service upgrade and billing management through hosted Stripe Checkout/Portal.
- Verified webhook inbox, subscription projection, and reconciliation path.
- Product surfaces on web and Mac reflect plan, usage, and billing state honestly.

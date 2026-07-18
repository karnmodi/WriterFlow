# ADR-0009: Stripe and paid enforcement are explicitly out of scope for Phase 5

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

A Stripe-ready schema is useful to design now (entitlement/subscription tables are
part of the Stage 5.1 PostgreSQL baseline), but implementing live Stripe
Checkout/webhooks/entitlement enforcement in Phase 5 would couple three
high-risk migrations at once: transport trust boundary, local encryption, and
payment state (`phases/phase-5-v2-cloud-foundation.md`, Known implementation
hazards).

## Decision

Phase 5 ships a free-alpha entitlement grant source only (enough to satisfy quota
reservation and the usage ledger) and no Stripe integration, no paid gate, and no
subscription enforcement. Stripe Checkout, Billing, Entitlements, Customer Portal,
and webhook reconciliation are Phase 7 work, built on top of Phase 5's proven
identity, entitlement-projection, and usage-ledger foundation.

## Consequences

- `entitlement_grants` / `entitlement_projection` tables exist in the Stage 5.1
  migrations, but only a free-alpha grant path is exercised until Phase 7.
- No `/v2/billing/*` route is implemented or reachable in Phase 5.
- Usage is metered from the first backend call (every provider stage gets an
  immutable ledger record) so that Phase 7 can reconcile real, already-measured
  cost/latency data before setting any price — but no charge is ever created in
  Phase 5.

## Revisit when

Phase 5 exit criteria pass and Phase 7 (Memberships, usage pricing, and Stripe)
begins.

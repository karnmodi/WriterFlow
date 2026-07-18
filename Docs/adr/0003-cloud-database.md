# ADR-0003: Cloud source of truth is Azure Database for PostgreSQL Flexible Server

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

V2's hard problems are relational and transactional: one external identity maps to
one user; a user belongs to organizations with roles; subscriptions produce
entitlements; inference must atomically reserve quota and record idempotency;
Stripe webhooks arrive more than once and out of order; usage must reconcile
exactly to billing; every query needs a tenant boundary (`V2-ARCHITECTURE.md` §8.5).

## Decision

Use one Azure Database for PostgreSQL Flexible Server per environment, private
endpoint only, as the source of truth for `users`, `organizations`,
`organization_memberships`, `devices`, `privacy_preferences`,
`entitlement_projection`, `usage_ledger`/`usage_balances`,
`quota_reservations`, `stripe_events`, and `outbox_events`. Enable row-level
security with `FORCE ROW LEVEL SECURITY` on every tenant-owned table; the runtime
application role does not own tenant tables and does not have `BYPASSRLS`.

## Consequences

- Unique/foreign/check constraints and transactions carry the correctness
  guarantees for idempotency, quota reservation, and append-only ledger
  enforcement — not application-level locking alone.
- RLS is defense in depth; application code still sets tenant context
  transaction-locally and retains explicit tenant predicates. Pooled connections
  must be tested for tenant-context bleed before production traffic.
- No document database, Cosmos DB, or vector store is introduced for this data.
  Redis or a queue service is added later only after measurement shows PostgreSQL
  projections/APIM counters cannot meet load (`V2-ARCHITECTURE.md` §9.3, §14.1).
- The production server's customer-managed-key (CMK) mode must be decided before
  server creation — Azure documents that this cannot be changed afterward.

## Revisit when

A defined feature needs semantic/vector search, or measured load shows PostgreSQL
projections cannot serve the entitlement/quota hot path — not before.

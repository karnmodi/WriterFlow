# V2 cloud data retention and deletion policy

**Status:** Stage 5.0 deliverable — closes the open item tracked in
`v2-data-inventory.md` §7 ("Open follow-up").
**Date:** 2026-07-18
**Scope:** the tables Stage 5.1 actually migrates (`phases/phase-5-v2-cloud-foundation.md`
Stage 5.1 → PostgreSQL baseline). `billing_customers`, `subscriptions`, `stripe_events`,
`classifier_feedback`, `user_data_keys`, `personalization_profiles`, and
`personalization_rules` are Phase 7 tables (ADR-0009: Stripe/personalization sync are out
of Phase 5) and get their own retention policy when their migrations are written — they
are out of scope here.

This exists so no Stage 5.1 migration ships a table without a decided retention default,
a decided deletion trigger, and a decided deletion mechanism, per the phase-wide
non-negotiable that content stays absent from the cloud database by default
(`V2-ARCHITECTURE.md` §7.3: ephemeral inference is the default retention mode).

## Policy table

| Table | Retention default | Deletion trigger | Mechanism | Notes |
|---|---|---|---|---|
| `users` | Indefinite while account active | Account deletion request | Soft-delete (`status = deleted`) immediately; hard-delete row after tombstone/backup-expiry window (§ below) | No password hash stored; row itself is not sensitive content |
| `auth_identities` | Indefinite while account active | Account deletion; identity unlink | Hard-delete row immediately on unlink; cascades on account hard-delete | `(issuer, subject)` unique pair — deleting frees it for reuse only after hard-delete |
| `organizations` | Indefinite while any membership active | Last member's account deletion | Soft-delete personal org with owner; hard-delete on the same schedule as `users` | Team orgs (future) get an explicit org-deletion flow, not covered here |
| `organization_memberships` | Indefinite while membership active | Membership revoked; account deletion | Hard-delete row on revoke; cascades on account hard-delete | Not append-only — safe to hard-delete |
| `devices` | Indefinite while device active | Device revoke; account deletion | Soft-delete (`revoked_at` set) immediately per §5.4; hard-delete row after 90 days | Retaining revoked rows briefly supports abuse investigation and reuse-detection audit trails |
| `privacy_preferences` | Indefinite while account active | Account deletion | Hard-delete on account hard-delete | Consent history (version + timestamp) is short, structured, non-content — no independent retention limit needed |
| `inference_requests` | 30 days | Account deletion; scheduled expiry job | Hard-delete rows older than 30 days via scheduled job; immediate hard-delete queued on account deletion | No text; row is state/metadata (user/org/device, operation key, intent, route class, prompt version, timestamps) needed for abuse/latency investigation, not indefinitely |
| `quota_reservations` | 7 days after commit/release | Reconciliation job (Stage 5.5) | Hard-delete via scheduled job once committed/released and past the abuse-investigation window | Stuck (never committed/released) reservations are reconciled, not silently deleted — see Stage 5.5 reconciliation job |
| `usage_ledger` | 7 years (financial/audit record) | Never deleted while account exists; anonymized on account hard-delete | Append-only; corrections are reversing entries, never mutation/deletion (phase-wide non-negotiable + Stage 5.5). On account hard-delete, null out the `user_id`/`org_id` foreign keys to a tombstone sentinel and retain the row for financial reconciliation | This is the one table that survives account deletion in anonymized form — required for provider-cost/billing reconciliation and audit |
| `usage_balances` | Indefinite while account active | Account deletion | Hard-delete on account hard-delete | Derived/projected from `usage_ledger`; safe to drop, recomputable in principle |
| `pricing_versions` | Indefinite (immutable, account-independent) | Never | Never deleted | Not user data — a versioned provider-cost-to-billable-unit conversion table shared across all accounts |
| `entitlement_grants` | Indefinite while account active; superseded grants kept | Account deletion | Hard-delete on account hard-delete | Grant history (trial, promo, admin, free-alpha) is small and structured; keeping superseded grants explains current `entitlement_projection` state until deletion |
| `entitlement_projection` | Indefinite while account active | Account deletion | Hard-delete on account hard-delete | Fast-path derived view; safe to drop and recompute from `entitlement_grants` in principle |
| `outbox_events` | 30 days after successful dispatch | Scheduled expiry job | Hard-delete via scheduled job once dispatched and past a short replay/debug window | Transactional outbox for async processing (Stage 5.5 usage reconciliation, future Stripe/email); not a long-term record |

## Account deletion sequencing (applies across the table above)

Per `V2-ARCHITECTURE.md` §5.4 "Delete account":

1. Disable inference immediately (reject new `inference_requests` inserts for the account).
2. Cancel scheduled billing according to policy (Phase 7 — no-op in Phase 5, no Stripe yet).
3. Record a deletion tombstone keyed by user ID before any row deletion, so a
   restore-from-backup reapplies the deletion rather than resurrecting the account.
4. Queue and execute hard-delete of `users`, `auth_identities`, `organizations` (personal
   org only, if this was the last member), `organization_memberships`, `devices`,
   `privacy_preferences`, `usage_balances`, `entitlement_grants`,
   `entitlement_projection` per the mechanisms above.
5. Anonymize (not delete) `usage_ledger` rows for the account — null the tenant foreign
   keys to a tombstone sentinel, keep the financial/audit fields.
6. Expire `inference_requests`, `quota_reservations`, and `outbox_events` rows for the
   account through their normal scheduled-expiry jobs rather than a special-cased path,
   since they already carry no text and a short default retention.
7. Re-apply the tombstone on every backup/PITR restore until backups themselves expire,
   per the backup retention window (Stage 5.1 PostgreSQL provisioning task).

## Deferred / explicitly not decided here

- Backup/PITR retention window length (owned by Stage 5.1 "Provision Azure Database for
  PostgreSQL Flexible Server ... backups/PITR" task — the tombstone-reapplication step
  above depends on that window once it is set, it does not set it).
- Phase 7 tables (`billing_customers`, `subscriptions`, `stripe_events`,
  `classifier_feedback`, `user_data_keys`, `personalization_profiles`,
  `personalization_rules`) — retention decided when their migrations are written, per
  `V2-ARCHITECTURE.md` §7.3's "Product improvement consent (separate, future)" and
  "Personalization sync (opt-in)" modes.

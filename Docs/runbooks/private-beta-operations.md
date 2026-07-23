# Private-beta operations

This runbook covers metadata-only operational response. Never paste drafts, context,
prompts, model output, access/refresh tokens, connection strings, or Key Vault values
into tickets, dashboards, commands, or chat.

## Release and rollback

1. Promote the same commit SHA through `staging` and then the protected `production`
   GitHub environment. Do not rebuild between environments.
2. Require green service, website, migration, Bicep, image, dependency, and secret
   scans. Run browser sign-up/pairing and every explicit action through APIM.
3. Start with the internal cohort, then opt-in private-beta accounts. Keep
   `WRITERFLOW_COHORT_BYO_FALLBACK=false` unless incident command explicitly enables
   rollback.
4. Watch auth failures, 5xx, p50/p95 first-delta latency, SSE disconnects, provider
   saturation, ledger reconciliation, PostgreSQL/Key Vault health, and Azure budget.
5. If a promotion fails, the deployment workflow returns API and website traffic to
   the previously active revisions. Verify `/healthz`, `/readyz`, JWKS, sign-in,
   pairing, one inference action, and ledger balance after rollback.
6. If cloud inference is unsafe but authentication remains healthy, disable the cloud
   cohort. Enable legacy BYO fallback only for the migration cohort and record the
   incident owner, expiry, and affected account IDs.

Before expanding a cohort, manually verify Accessibility focus, secure-field inertness,
non-activating preview, review-before-replace, and clipboard fallback in Apple Notes,
Mail, TextEdit, Safari, Chrome, Slack, WhatsApp Desktop, and Notion. Record OS/app
versions and results without recording entered text.

## Authentication or Entra outage

1. Confirm Entra discovery/JWKS health and compare `/auth/callback` failures by safe
   request ID. Do not expose upstream error bodies to users.
2. Preserve existing device sessions while refresh remains safe; do not bypass issuer,
   audience, device-revocation, user-status, or PKCE checks.
3. Pause new private-beta invitations. If the WriterFlow token issuer is affected,
   disable inference admission rather than accepting unverifiable tokens.
4. Restore, test sign-up, sign-in, logout, pairing expiry, refresh rotation, reuse
   detection, and revoked-device rejection, then reopen invitations.

## WriterFlow ES256 signing-key rotation

1. Create a new P-256 Key Vault key; never export private key material.
2. Set it as `JWT_SIGNING_KEY_NAME` and retain the retired key names in
   `JWT_SIGNING_PREVIOUS_KEY_NAMES`.
3. Deploy staging, verify JWKS contains current and previous public keys, and verify
   both old unexpired and newly issued tokens.
4. Promote production. Keep each previous public key published beyond the maximum
   access-token lifetime plus clock skew.
5. Remove a retired key only after that overlap and confirm no requests use its `kid`.

## PostgreSQL backup and restore

1. Confirm Azure automated backup health and retention before every schema promotion.
2. Restore to a new private server at a point before the incident; never overwrite the
   source server.
3. Validate migration level, row-level security, append-only ledger triggers, balance
   reconciliation, disabled users, and revoked devices using least-privilege roles.
4. Rotate database secrets in Key Vault, deploy new secret references, and switch only
   after staging probes pass. Retain the old server until reconciliation is signed off.
5. Follow `postgres-cmk-rotation.md` separately for encryption-key incidents.

## Model saturation or regional failure

1. Confirm 429/timeout/first-delta telemetry by logical route, without inspecting user
   content.
2. Disable the unhealthy primary route. Fallback is allowed only before the first
   output delta; never restart a partially emitted operation against another model.
3. Point the logical route to an approved deployment with compatible prompt contract,
   run every explicit-action fixture, and compare p50/p95 latency and error rate.
4. Restore the original route only after quota and health remain stable through the
   observation window.

## Account disable or deletion

1. Authenticate the support request and record only immutable issuer/subject and
   WriterFlow account IDs.
2. Disable immediately to block device token polling, refresh, and authenticated API
   access. Revoke every device token family.
3. Process deletion through the documented retention/deletion registry and outbox;
   never edit append-only usage ledger history in place.
4. Confirm cloud account data deletion and tell the user how to remove the local,
   account-scoped SQLCipher database. Do not claim deletion before both checks pass.

## Exit gate

Production remains closed if direct-origin gateway-bypass probes, PostgreSQL
firewall/TLS, Key Vault RBAC, Azure OpenAI managed-identity-only access, canary
no-content log inspection, encrypted migration/recovery, browser auth, Mac pairing,
all explicit actions, quota race/replay, cross-tenant isolation, telemetry, rollback,
or support ownership is unverified. Stripe charging and Phase 6 auto-selection remain
disabled.

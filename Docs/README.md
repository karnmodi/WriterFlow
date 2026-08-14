# Docs — v2 planning and contract artifacts

Stage 5.0 (`phases/phase-5-v2-cloud-foundation.md`) deliverables. Read `CLAUDE.md`'s
source-of-truth order first; this directory is the next layer down, produced *from*
`PRD-V2.md` / `V2-ARCHITECTURE.md` / `V2-ROADMAP.md`, not a replacement for them.

| Path | What it is |
|---|---|
| `adr/0001`–`0015` | Short ADRs freezing the Phase 5 decisions in reviewable one-decision-per-file form. ADR-0010/0011/0012 supersede in-app MSAL auth and mandatory Developer ID; ADR-0015 uses Developer APIM plus a Key Vault-backed origin credential for the cost-controlled private beta while deferring Standard v2. |
| `v2-data-inventory.md` | Every place v1 currently stores data, classified, built from direct source inspection — not inferred. |
| `v2-threat-model.md` | The Stage 5.0-required threat model, one entry per named threat with mitigation and residual risk. |
| `contracts/openapi.yaml` | REST endpoints (device pairing `/v2/device/*` + `/v2/token/refresh`, `/v2/me`, devices, style analysis, personalization, usage, billing stubs, account deletion). |
| `contracts/inference-stream.md` | `POST /v2/inference/stream` request/event/state contract — the one high-risk endpoint every v1 action must pass through with parity. |
| `contracts/schemas/*.schema.json` | JSON Schema for the inference request envelope and the discriminated SSE event union referenced by the above. |
| `v2-data-retention-policy.md` | Per-cloud-table retention default, deletion trigger, and deletion mechanism for every table Stage 5.1 migrates, plus account-deletion sequencing. |
| `contracts/fixtures/` | Schema-validated request/event/redaction/prompt-injection test fixtures for the Stage 5.1 TypeScript harness to load (see its own `README.md`). |
| `plans/api-only-prompt-composition-plan.md` | Detailed Stage 6.4-compatible plan for server-only prompt differentiation, evaluation, latency gates, and rollout without a Mac client/configuration change. |
| `plans/api-only-prompt-composition-baseline.md` | M0 exact-prompt snapshots, compatibility freeze, quality rubric, compiler measurements, deployed metadata-only timing baseline, and remaining closure gaps. |
| `plans/api-only-prompt-composition-evidence.md` | Stage 6.4 implementation, automated gates, immutable candidate, isolated Azure evaluation, rollback, and production go/no-go evidence. |
| `../prompts/README.md` | Stage 6.4 server prompt manifest, compiler trust boundaries, versioning, evaluation, and isolated candidate-route operations. |

**Status: draft, not yet signed off.** Stage 5.0's Accept criterion is architecture
review sign-off on this package before any Stage 5.1 database migration or backend
code becomes a release dependency. All Stage 5.0 checklist items are now written; the
architecture-review sign-off itself is the remaining gate before Stage 5.1 database
migrations become a release dependency.

## Runbooks

Not Stage 5.0 contract deliverables — operational docs added as later stages needed
them. See `V2-ARCHITECTURE.md` §14's planned `docs/runbooks/` location.

| Path | What it is |
|---|---|
| `runbooks/v2-setup-testing.md` | Stage 5.2: personal step-by-step plan to stand up an Entra External ID tenant, run the stack locally, and pair a real device end to end for free, plus the optional paid Azure deployment. |

# Docs — v2 planning and contract artifacts

Stage 5.0 (`phases/phase-5-v2-cloud-foundation.md`) deliverables. Read `CLAUDE.md`'s
source-of-truth order first; this directory is the next layer down, produced *from*
`PRD-V2.md` / `V2-ARCHITECTURE.md` / `V2-ROADMAP.md`, not a replacement for them.

| Path | What it is |
|---|---|
| `adr/0001`–`0012` | Short ADRs freezing the Phase 5 decisions in reviewable one-decision-per-file form. ADR-0010/0011/0012 (2026-07-18) supersede the in-app MSAL auth (0002) and mandatory Developer ID (0008): auth/membership move to the browser, the Mac pairs via a device flow for a WriterFlow-minted token, and v2 keeps v1's ad-hoc distribution with no Apple Developer account. |
| `v2-data-inventory.md` | Every place v1 currently stores data, classified, built from direct source inspection — not inferred. |
| `v2-threat-model.md` | The Stage 5.0-required threat model, one entry per named threat with mitigation and residual risk. |
| `contracts/openapi.yaml` | REST endpoints (device pairing `/v2/device/*` + `/v2/token/refresh`, `/v2/me`, devices, style analysis, personalization, usage, billing stubs, account deletion). |
| `contracts/inference-stream.md` | `POST /v2/inference/stream` request/event/state contract — the one high-risk endpoint every v1 action must pass through with parity. |
| `contracts/schemas/*.schema.json` | JSON Schema for the inference request envelope and the discriminated SSE event union referenced by the above. |
| `v2-data-retention-policy.md` | Per-cloud-table retention default, deletion trigger, and deletion mechanism for every table Stage 5.1 migrates, plus account-deletion sequencing. |
| `contracts/fixtures/` | Schema-validated request/event/redaction/prompt-injection test fixtures for the Stage 5.1 TypeScript harness to load (see its own `README.md`). |

**Status: draft, not yet signed off.** Stage 5.0's Accept criterion is architecture
review sign-off on this package before any Stage 5.1 database migration or backend
code becomes a release dependency. All Stage 5.0 checklist items are now written; the
architecture-review sign-off itself is the remaining gate before Stage 5.1 database
migrations become a release dependency.

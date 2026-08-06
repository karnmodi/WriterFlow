# Phase 8 — GA hardening and release (V2)

Source: [V2-ROADMAP.md](../V2-ROADMAP.md) Phase 8 and [PRD-V2.md](../PRD-V2.md) §10.3.

## Stage 8.1 — Security and privacy gate
- [ ] Threat-model review sign-off
- [ ] RLS / tenant-isolation integration tests for every table
- [ ] Secret and artifact scans clean on release branch
- [ ] Private networking verified (no public origin/DB/Key Vault/provider)
- [ ] Account deletion and export runbooks tested

**Accept:** security review checklist signed; no CRITICAL/HIGH unfixed findings.

## Stage 8.2 — Reliability and cost gate
- [ ] APIM SSE load test (scripts/load/apim-sse-load.mjs)
- [ ] Autoscale and concurrency tuning documented
- [ ] 8+ hour soak with alerting
- [ ] Provider spend ceilings enforced

**Accept:** SLOs defined; soak passes without data loss or quota drift.

## Stage 8.3 — v1 migration rollout
- [ ] Staged cohort rollout with kill switches
- [ ] SQLCipher interruption tests on real hardware matrix
- [ ] Remove BYO production path only after rollback confidence

**Accept:** migration cohort completes; rollback tested without app release.

## Stage 8.4 — Distribution release gate
- [x] Universal arm64+x86_64 ad-hoc Release build and artifact/deployment-target verifier
- [ ] Ad-hoc DMG + SHA-256 + manual Gatekeeper docs (ADR-0010)
- [ ] Runtime matrix: latest macOS 14, 15, and 26 on Apple silicon and supported Intel hardware; include a clean macOS 14 minimum-version install
- [ ] Pairing survives app updates
- [ ] Public pricing, privacy, retention, subprocessor disclosure
- [ ] Support and account-deletion paths live

**Accept:** GA release notes published; staged rollout monitored.

## Phase 8 exit criteria
- [ ] All Stage 8.1–8.4 acceptance criteria pass
- [ ] PRD-V2 §10.3 GA gates closed
- [ ] v2.0.0 tag and release artifact published

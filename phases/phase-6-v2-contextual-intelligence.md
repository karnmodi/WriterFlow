# Phase 6 — Contextual intelligence (V2)

Source: [V2-ROADMAP.md](../V2-ROADMAP.md) Phase 6. The implementation is cohort-off by
default; do not remove rollback compatibility or enable auto mode broadly until the
classifier and live-shadow thresholds pass.

## Stage 6.1 — Target identity + eval set
- [x] Define the nine-skill taxonomy and reviewed manifests in `prompts/skills.yaml`
- [x] Build a deterministic 330-case cross-app evaluation harness in `prompts/classifier/`
- [x] Record menu/recommendation limitations and deterministic-rule baseline without real user history

**Accept:** harness runs locally and in CI; baseline metrics recorded.

## Stage 6.2 — ContextSignalBuilder + deterministic rules
- [x] Implement `ContextSignalBuilder`, `ContextCapsuleStore`, and opaque `TargetFingerprint`
- [x] Keep active-field context volatile/local with debounce, expiry, and lifecycle clearing
- [x] Implement high-confidence deterministic routing with neutral `improve` fallback

**Accept:** ≥95% acceptable-route precision on high-confidence rules in eval set.

## Stage 6.3 — Server classifier + model router
- [x] Scaffold `POST /v2/classifier/evaluate` route (returns `not_implemented` until model wired)
- [x] Keep `/classifier/evaluate` restricted to local/eval use
- [x] Run `classifier_fast` internally in `/inference/stream` only for ambiguity
- [x] Meter classifier and bounded specialist attempts with immutable stage keys/attempt numbers
- [ ] Meet exact/acceptable accuracy and real-region latency gates

**Accept:** ≥85% exact-intent, ≥95% acceptable-route; ambiguous first-delta p95 <2.5s.

## Stage 6.4 — PromptPlan + enhancer
- [x] Compile versioned first-party `SkillManifest` resources into existing reviewed prompt plans
- [x] Enforce manifest guardrails in every writer invocation and keep prompt enhancement adaptive/idempotent
  - Simple requests remain natural messages; structure appears only for meaningful constraints or deliverables.
  - Relevant chat/email context may resolve references, but whole threads and stock requirements are never restated.
- [x] Distinguish completed thread drafts from unfinished continuations; never append generic next-step filler
- [x] Route prompt/code destinations through `prompt_enhancer`
- [x] Record skill/prompt version and logical route without prompt content
- [ ] Prove prompt-policy quality in production-model regression evals

**Accept:** no prompt deploy without regression eval pass.

## Stage 6.5 — AutoActionCoordinator (remove options menu)
- [x] Implement `AutoActionCoordinator` in the Mac app
- [x] Implement explicit trigger → first-delta preview → word-coalesced stream → Enter/Replace
- [x] Add Shift-click and collision-checked `⌃⌥⇧ Space` natural-language composer
- [x] Add Replace/Copy/Adjust/Discard, Retry after failure or completion, and revalidation-before-Replace
  - Retry keeps the prior result visible until the new stream's first delta and restores it on failure.
  - Retry lineage resolves the client operation ID to the tenant-scoped server request ID before persistence.
- [x] Keep the legacy menu behind a server cohort flag; auto mode defaults off
- [ ] Remove the legacy normal-menu code after one stable 100% release

Local verification (2026-08-18): migration 015, the local API, standard Entra device
pairing, post-pairing cohort refresh, and an authenticated `mode=auto` SSE stream all
passed. The running debug cohort enters auto mode; production remains unchanged.

**Accept:** no wrong-field replacement; secure fields remain inert.

## Stage 6.6 — Personalized classifier
- [x] Content-free accepted/adjusted/discarded feedback capture
- [ ] Personalized routing without passive uploads

**Accept:** reduces corrections without hurting safety metrics.

## Phase 6 exit criteria
- [ ] Classifier thresholds met on eval + live shadow cohort
- [x] Auto-action UX implemented behind cohort flag
- [x] Classifier/enhancer/generator usage metered per provider attempt
- [ ] Phase 7 can begin from stable telemetry

# Phase 6 — Contextual intelligence (V2)

Source: [V2-ROADMAP.md](../V2-ROADMAP.md) Phase 6. Do not remove the normal options menu until classifier thresholds pass.

## Stage 6.1 — Target identity + eval set
- [ ] Define intent/route taxonomy in `prompts/classifier/`
- [ ] Build deterministic 300+ case evaluation harness
- [ ] Score recommendations without real user history

**Accept:** harness runs locally and in CI; baseline metrics recorded.

## Stage 6.2 — ContextSignalBuilder + deterministic rules
- [ ] Implement `Sources/WriterFlow/Engine/ContextSignalBuilder.swift`
- [ ] Privacy-bounded signals (no passive uploads)
- [ ] High-confidence deterministic routing rules

**Accept:** ≥95% acceptable-route precision on high-confidence rules in eval set.

## Stage 6.3 — Server classifier + model router
- [x] Scaffold `POST /v2/classifier/evaluate` route (returns `not_implemented` until model wired)
- [ ] Wire real classifier model behind private Azure OpenAI
- [ ] Meter classifier as separate ledger stage

**Accept:** ≥85% exact-intent, ≥95% acceptable-route; ambiguous first-delta p95 <2.5s.

## Stage 6.4 — PromptPlan + enhancer
- [ ] Versioned `PromptPlan` compilation from `prompts/`
- [ ] Prompt enhancer with regression eval gate
- [ ] Prompt version in telemetry

**Accept:** no prompt deploy without regression eval pass.

## Stage 6.5 — AutoActionCoordinator (remove options menu)
- [ ] Implement `AutoActionCoordinator` in Mac app
- [ ] type → hotkey → preview → Enter flow
- [ ] Remove normal options menu only after Stage 6.3 thresholds pass

**Accept:** no wrong-field replacement; secure fields remain inert.

## Stage 6.6 — Personalized classifier
- [ ] Correction capture (opt-in)
- [ ] Personalized routing without passive uploads

**Accept:** reduces corrections without hurting safety metrics.

## Phase 6 exit criteria
- [ ] Classifier thresholds met on eval + live shadow cohort
- [ ] Auto-action UX replaces options menu
- [ ] Classifier/enhancer usage metered per stage
- [ ] Phase 7 can begin from stable telemetry

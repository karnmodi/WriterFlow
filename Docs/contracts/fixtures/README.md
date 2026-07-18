# Stage 5.0 test fixtures

**Status:** Stage 5.0 deliverable — closes the "Test fixtures" checklist in
`phases/phase-5-v2-cloud-foundation.md` Stage 5.0.

These are data-only fixtures validated against `Docs/contracts/schemas/*.schema.json`
and the state machine in `Docs/contracts/inference-stream.md`. They exist so Stage 5.1's
TypeScript test harness (`services/api` contract tests, per Stage 5.1 "Repository
structure") has real, reviewed fixtures to load on day one instead of inventing ad hoc
payloads mid-implementation. No test *runner* code lives here — that lands with the
Stage 5.1 workspace, wired to read these files.

## Layout

| Path | Covers |
|---|---|
| `requests/*.json` | One `InferenceRequestEnvelope` per current `WritingAction`, plus empty Reply, Custom (append + `---INSERT---` mode), Prompt Builder analyze/finalize, and the separate `StyleAnalysisRequest`. Each validates against `inference-request.schema.json`. |
| `events/*.json` | One SSE event sequence per lifecycle case: happy-path completion, Prompt Builder analyze (questions instead of deltas), cancellation, timeout, 429, 5xx, and a disconnected stream. Each event validates against `sse-events.schema.json`; ordering matches `inference-stream.md`'s canonical sequence. |
| `redaction/canary-secrets.json` | Requests containing planted canary secrets in every free-text field, for the redaction test: prove canaries never reach logs, traces, errors, or `usage_ledger`/`inference_requests` rows (`inference-stream.md` "Allowed log fields"). |
| `prompt-injection/injection-vectors.json` | Untrusted-text injection attempts planted in conversation, draft, Custom instruction, personalization, and Prompt Builder answers. Each fixture states the property an attacker targets and the expected-safe outcome, for the prompt-injection test (threat model `Docs/v2-threat-model.md`). |

## How Stage 5.1 should consume these

- Load each `requests/*.json` file, validate against `inference-request.schema.json`,
  and (once `services/api` exists) POST it against a stubbed/mocked provider to assert
  the canonical event order in the matching `events/*.json` fixture.
- Load `redaction/canary-secrets.json`, run each request through the real logging path,
  and grep all emitted logs/traces/DB rows for every planted canary string — the test
  fails if any canary appears anywhere outside the fixture file itself.
- Load `prompt-injection/injection-vectors.json` and assert the documented
  `expectedSafeOutcome` for each vector — none may change authorization, retention,
  tool use, deployment/route selection, or output mode outside the validated envelope.

## Non-goals

These fixtures are not exhaustive load/fuzz corpora and do not replace the Stage 5.1
integration tests that exercise a real (mocked-provider) server. They are the minimum
reviewed set the Stage 5.0 checklist calls for: one fixture per named scenario.

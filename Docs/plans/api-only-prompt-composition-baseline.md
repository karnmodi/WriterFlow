# API-only prompt composition M0 baseline

**Captured:** August 6, 2026  
**Baseline commit:** `578600b` (`v2.0.2`) plus the uncommitted planning document only  
**Status:** Local compiler/contract baseline complete; production timing baseline partial

This document freezes the behavior that exists before M1 changes prompt selection or
composition. It contains no prompt, field, conversation, or output content from real
users. Exact prompt snapshots use the repository's synthetic contract fixtures.

## Exact prompt evidence

The immutable pre-change snapshot is checked in at
`Docs/plans/evidence/api-only-prompt-composition-m0.snap`. It captures the exact system
prompt, user prompt, logical route, output-mode hint, completion ceiling, character
counts, and a clearly labeled `ceil(characters / 4)` token estimate. The active Vitest
snapshot now protects the candidate behavior and is intentionally not the M0 baseline.

Coverage:

- all seven actions: Elaborate, Formal, Casual, Fix Grammar, Reply, Custom, and Prompt
  Builder analyze;
- Prompt Builder finalize as a separate compatibility/gap characterization;
- six Reply destination classes: email, chat, LinkedIn, LLM chat, coding chat, and
  unknown/default;
- the existing selection, Custom insert-mode, app-tone, and inline-personalization
  behavior.

The snapshot is the exact baseline. The token estimate is only an offline comparison
signal; model-reported prompt tokens remain authoritative when a provider request is
made.

## Local prompt-size and compiler baseline

Measured on Node `v24.14.1` after one warm-up pass. The run compiled 14 cases 500 times
each (7,000 samples) from the same synthetic fixtures and current Markdown assets.

| Action | System chars | User chars | Total chars | Estimated tokens |
|---|---:|---:|---:|---:|
| Elaborate | 1,569 | 50 | 1,619 | 405 |
| Formal | 1,268 | 97 | 1,365 | 342 |
| Casual | 2,110 | 183 | 2,293 | 574 |
| Fix Grammar | 1,271 | 75 | 1,346 | 337 |
| Reply | 3,382 | 99 | 3,481 | 871 |
| Custom | 3,117 | 134 | 3,251 | 813 |
| Prompt Builder analyze | 1,535 | 126 | 1,661 | 416 |
| Prompt Builder finalize | 1,535 | 193 | 1,728 | 432 |

Warm compile duration was p50 `0.0273 ms`, p95 `0.0463 ms`, and max `0.2930 ms`.
This is a local OS-cache-warm measurement, not proof that the current synchronous
per-request file reads are an acceptable production design. M1 still replaces those
reads with startup validation and an in-memory asset cache.

## Deployed timing baseline

The fixed Log Analytics window was `2026-07-23T19:16:00Z` through
`2026-08-06T22:12:00Z`. Queries selected only `event`, `route`, `latencyMs`, opaque
request ID, and event timestamps from `ContainerAppConsoleLogs_CL`.

### Provider-start to first output delta

| Logical route | Samples | p50 | p95 | Min | Max |
|---|---:|---:|---:|---:|---:|
| `rewrite_standard` | 73 | 1,142 ms | 3,881 ms | 623 ms | 7,968 ms |
| `grammar_fast` | 14 | 1,256 ms | 8,192 ms | 720 ms | 8,192 ms |
| `prompt_enhancer` | 47 | 956 ms | 3,572 ms | 662 ms | 3,630 ms |

### API accepted to API completed

| Logical route | Samples | p50 | p95 | Min | Max |
|---|---:|---:|---:|---:|---:|
| `rewrite_standard` | 73 | 2,047 ms | 8,234 ms | 0 ms | 9,981 ms |
| `grammar_fast` | 14 | 2,039 ms | 8,917 ms | 635 ms | 8,917 ms |
| `prompt_enhancer` | 47 | 5,017 ms | 9,990 ms | 800 ms | 10,902 ms |

These are API-origin measurements for requests that reached the service through the
deployed edge. They are not client-observed APIM request-to-visible-delta measurements,
do not separate warm/cold/token-acquisition cases, and do not include output length.
Those missing dimensions remain an M0/M4 evidence gap and must not be reported as a
passed latency gate. The data already shows that current p95 timing misses the proposed
2.5-second target on every logical route.

The normal successful route uses exactly one provider invocation; this is locked by
`routePool.test.ts`. A failed primary may still use the already-approved pre-first-delta
fallback attempt, and no fallback is permitted after a primary delta.

## Frozen no-client-change contract

M1-M5 must preserve all of the following unless this plan is explicitly revised:

- request schema and field caps in `InferenceRequestEnvelopeSchema` and the versioned
  JSON Schema;
- the seven-value `WritingAction` enum;
- `replace` and `insert_before` output-mode values;
- canonical SSE order and event shapes;
- Prompt Builder's parser-visible `---CLARIFY---` and `---PROMPT---` markers;
- conversation budgets: 1,200 characters for normal rewrites, 2,000 for Custom, and
  4,000 for Reply and Prompt Builder;
- existing per-action completion-token ceilings;
- one provider call on a successful normal action; and
- no macOS source, binary, setting, request field, parser, or reconfiguration change.

## Reproducible baseline gaps

The baseline test deliberately characterizes these current deficiencies so M1/M2 can
change them intentionally:

1. Selection scope sends both `SELECTED TEXT` and the full `DRAFT` as transformation
   sources instead of selecting one canonical source.
2. Cloud Custom policy still instructs the model to emit the legacy `---INSERT---`
   marker even though output mode is already server-decided.
3. Prompt Builder does not load its analyze/finalize or fresh/continuation assets.
4. Email, chat, LinkedIn, and unknown Reply destinations all select the same default
   format; only generic LLM chat and Cursor currently differ.
5. `appTone` and enabled inline personalization do not affect compilation.
6. Prompt assets are read synchronously from disk on every request instead of validated
   and cached at startup.

## Quality scoring rubric

Each reviewed output receives a 1-5 score in every dimension. Reviewers compare outputs
blindly and record critical failures separately.

| Dimension | 1 | 3 | 5 |
|---|---|---|---|
| Factual preservation | Invents, drops, or changes a material fact | Preserves core facts with a minor non-material drift | Preserves every relevant fact, constraint, identifier, and commitment boundary |
| Instruction compliance | Misses or contradicts the requested operation | Satisfies the main instruction but misses a secondary constraint | Satisfies every explicit format, tone, length, include, and exclude constraint |
| Contextual specificity | Generic or unrelated to supplied context | Uses one relevant detail but remains partly generic | Uses exactly the thread details needed to make the result specific and correct |
| Platform fit | Wrong medium structure | Usable but contains mild medium mismatch | Natural for the destination's expected structure, length, greeting, and closing |
| Naturalness | Robotic, awkward, or template-like | Clear but noticeably generated or stiff | Human, fluent, and consistent with the source language/register |
| Minimality | Adds substantial unnecessary content | Some removable filler | No content beyond what the action and destination require |
| Parser validity | Missing/dual/malformed marker or unusable payload | Parseable only after lenient cleanup | Exactly one valid block or marker-free rewrite as required |

Critical failures are release-blocking regardless of aggregate score: invented people,
dates, availability, commitments, paths, or completion claims; Prompt Builder answering
the underlying task; Grammar changing already-correct wording; selection changing text
outside the selection; prompt/content leakage; malformed Prompt Builder output; or an
extra provider call.

## M0 closure status

- Product Owner confirmation was recorded on 2026-08-06 when Karan directed completion
  after the latency contract, no-client-change boundary, and deployment blockers were
  reported.
- Karan Modi is the named BE, PQ, QA, SEC, SRE, and PO owner for this solo project.
- A client-observed authenticated APIM benchmark recording first visible delta, full
  completion, output length, provider-reported prompt/output tokens, cold/warm and token
  acquisition state, and provider-call count per action/destination is in progress at
  `build/prompt-evals/production-baseline.json`.

No production prompt behavior changes are part of M0.

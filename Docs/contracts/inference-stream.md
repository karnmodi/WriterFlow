# `POST /v2/inference/stream` — request, event, and state contract

**Status:** Stage 5.0 deliverable
**Date:** 2026-07-17

This is the one high-risk, high-value endpoint in Phase 5: every existing v1 action
must pass through it with equivalent behavior (`phases/phase-5-v2-cloud-foundation.md`
Stage 5.4). Full JSON Schemas are in `Docs/contracts/schemas/`; this file is the
prose contract that ties them together — canonical ordering, state machine, retry
rules, and error codes.

## Request

```
POST /v2/inference/stream
Authorization: Bearer <access-token>
Content-Type: application/json
Accept: text/event-stream
Idempotency-Key: <uuid>
X-WriterFlow-Version: 2.0.0
X-WriterFlow-Device: <opaque-device-id>
```

Body: see `Docs/contracts/schemas/inference-request.schema.json`. `mode` is a
discriminant:

- **`explicit`** (Phase 5): `task.requestedAction` is one current `WritingAction`
  (`elaborate | formal | casual | fixGrammar | reply | custom | promptBuilder`).
  `custom` requires `task.customInstruction`. `promptBuilder` requires
  `task.promptBuilder = {phase: "analyze"|"finalize", flowId, brief, answers}`.
- **`auto`** (Phase 6, rejected in Phase 5): no `requestedAction`; the server derives
  intent from bounded context signals.

Every string field, total request bytes, context length, and output token budget is
capped server-side independent of any client-declared length. Unknown top-level
fields, unknown `mode`/`requestedAction`/`phase` values, or a `custom`/`promptBuilder`
request missing its conditionally-required field are rejected with
`VALIDATION_FAILED` before any provider work starts.

## Canonical SSE event order

```
request.accepted
decision                                  (exactly one)
[prompt_builder.questions]                (only for promptBuilder.phase = analyze, replaces deltas)
output.delta *                            (zero or more, only when not analyze-phase)
usage.summary                             (exactly one, non-analyze-phase)
completed
```

`error` is terminal and may appear at any point instead of the remaining sequence.
SSE comment lines (`:` keepalive) are transport-level and are not domain events —
clients must ignore them, not count them toward ordering. A client that receives an
`output.delta` before a `decision`, more than one `decision`, more than one
`usage.summary`, or an event type it does not recognize as forward-compatible must
treat the stream as invalid and discard any buffered output. See
`Docs/contracts/schemas/sse-events.schema.json` for the per-event payload shape.

`explicit` mode always returns `decision.confidence = null`; `auto` mode (Phase 6)
returns a measured confidence and reason code.

## Canonical operation state machine

```
reserved → running → streaming → completed
                                → failed
                                → cancelled
```

- **`reserved`**: request row + worst-case quota reservation created in one DB
  transaction, before any provider call.
- **`running`**: provider call in flight, no output yet.
- **`streaming`**: at least one `output.delta` has been sent to the client.
- **`completed`**: terminal success; `usage.summary` and `completed` have been sent;
  Replace/Copy become enabled client-side only now.
- **`failed`** / **`cancelled`**: terminal; no further deltas; ledger entry commits
  internal provider cost (if any was incurred) but zero customer billable units.

## Retry and idempotency rules

- Provider retry/failover is permitted only while state is `reserved` or `running`
  (i.e., before the first delta). Once `streaming`, a broken connection never
  triggers an automatic second provider call.
- Reusing a completed operation's `Idempotency-Key` returns its final status without
  calling the model again. The default ephemeral mode does not replay final text —
  the client keeps only the deltas it already received. Response:
  `409 REQUEST_CONFLICT` is not used here; the SSE stream itself replays the
  terminal state (`completed`/`failed`/`cancelled`) with no further deltas.
- **Retry** (user-initiated, e.g. after a broken stream) is a **new** operation with
  a new `Idempotency-Key` and `retryOf` pointing at the prior request ID. Only its
  own successful completion consumes customer billable units.
- The Mac client must never mint a second `Idempotency-Key` for the same user
  action automatically after output has begun — only an explicit user Retry does.

## Error codes

See `Docs/contracts/openapi.yaml` `ErrorCode` enum — the same closed set is used for
both REST responses and the terminal `error` SSE event:
`AUTH_REQUIRED, AUTH_INVALID, DEVICE_REVOKED, PLAN_REQUIRED, QUOTA_EXCEEDED,
RATE_LIMITED, TARGET_TOO_LARGE, MODEL_UNAVAILABLE, REQUEST_CONFLICT,
VALIDATION_FAILED, INTERNAL_ERROR`. Provider error bodies, deployment names, resource
hosts, and secrets are never forwarded — the `error` event carries only a code and
safe display copy.

## Allowed log fields

Structured logs and traces for this endpoint may include only: request ID,
user/org/device IDs (pseudonymous, never IdP subject/email in cleartext), `mode`,
`intent`, `route`, `promptVersion`, char/token counts, latency, operation state,
and the `ErrorCode` enum value. `draft`, `selectedText`, `conversation`,
`customInstruction`, `promptBuilder.answers`, `personalization.*`, and any raw
model output are forbidden in logs, traces, and the `usage_ledger`/
`inference_requests` tables — this is enforced by a logger allowlist (Stage 5.1),
not by convention, and verified by the canary-content test fixture (threat #12 in
`Docs/v2-threat-model.md`).

## What the client never sends

No full AX tree, no keystroke history, no clipboard history beyond the single
bounded field/selection/context already used by v1 actions, and no unrelated window
content. `site`, `windowClass`, and `signals.*` are hints for prompt assembly, not
authorization claims — the server does not trust them for access control.

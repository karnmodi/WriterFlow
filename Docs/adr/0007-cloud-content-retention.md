# ADR-0007: Inference content is ephemeral by default; personalization sync is opt-in

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

WriterFlow's local-first privacy posture (v1 golden rule: text leaves the Mac only
on explicit action) must survive the move to a cloud backend that necessarily sees
plaintext during inference. The backend must not become a passive content store.

## Decision

Raw field text, surrounding context, prompts, and model output are transient
within WriterFlow by default: excluded from gateway/application/analytics logs and
from cloud content tables. Only usage metadata persists (route class, token
counts, latency, status, opaque request IDs — never text). Cloud personalization
sync is a separate, explicit opt-in: if enabled, only a derived style
profile/rules payload is envelope-encrypted and stored (per-user DEK wrapped by a
versioned Key Vault KEK). Raw local conversation history sync is deferred
indefinitely and is not part of v2.0 scope.

## Consequences

- A broken/cancelled SSE stream cannot be "recovered" from server storage — the
  client retains only the deltas it already received; an explicit Retry is a new
  metered operation (`V2-ARCHITECTURE.md` §6.4).
- Live encrypted content/wrapped-key deletion is immediate on request, but
  PostgreSQL WAL/PITR backups still contain ciphertext and wrapped DEKs until the
  disclosed backup-retention window expires; deletion tombstones must be reapplied
  before any restore serves traffic.
- WriterFlow must say directly, in product copy, that this is not end-to-end
  encryption — the backend and model provider see request plaintext during
  inference.
- Product-improvement/model-training consent, if ever introduced, is a separate,
  future, explicitly-disclosed control — never implied by enabling sync.

## Revisit when

Cross-device raw history sync becomes a validated, explicitly scoped user need
(tracked as a decision deliberately left open in `PRD-V2.md` §12).

import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { InferenceRequestEnvelopeSchema, type InferenceStreamEvent } from "@writerflow/shared";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { ApiError, sendError } from "../errors.js";
import { commitInferenceRequest, QuotaExceededError, releaseInferenceRequest, reserveInferenceRequest, transitionState } from "../inference/accounting.js";
import type { InferenceProvider } from "../inference/provider.js";

/** Only requestedAction wired to a real accounting+provider path so far —
 * Stage 5.4's "Expand parity" adds the rest of the current v1 actions. */
const ROUTE = "grammar_fast";
const PROMPT_VERSION = "grammar@5.1.0";

/**
 * POST /v2/inference/stream — Docs/contracts/inference-stream.md. The first
 * (and, until Stage 5.4's "Expand parity" work lands, only) vertical slice:
 * explicit Fix Grammar only. Every code path — happy stream, quota
 * exceeded, provider error, client disconnect — commits or releases the
 * reservation created up front; none may leave one dangling.
 */
export function registerInferenceRoutes(app: FastifyInstance, pool: pg.Pool, keys: SigningKeyProvider, provider: InferenceProvider): void {
  app.post("/inference/stream", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);

    const idempotencyKey = request.headers["idempotency-key"];
    const clientVersion = request.headers["x-writerflow-version"];
    const clientDevice = request.headers["x-writerflow-device"];
    if (typeof idempotencyKey !== "string" || idempotencyKey.length === 0) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Idempotency-Key header is required."));
      return;
    }
    if (typeof clientVersion !== "string" || clientVersion.length === 0) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "X-WriterFlow-Version header is required."));
      return;
    }
    if (clientDevice !== ctx.deviceId) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "X-WriterFlow-Device header must match the authenticated device."));
      return;
    }

    const parsed = InferenceRequestEnvelopeSchema.safeParse(request.body);
    if (!parsed.success) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Request body failed schema validation."));
      return;
    }
    const envelope = parsed.data;

    if (envelope.mode !== "explicit") {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "mode 'auto' is Phase 6 — Phase 5 only accepts 'explicit'."));
      return;
    }
    if (envelope.task.requestedAction !== "fixGrammar") {
      sendError(
        reply,
        new ApiError(
          "VALIDATION_FAILED",
          400,
          "Only requestedAction 'fixGrammar' is implemented so far — Stage 5.4's 'Expand parity' work is still open."
        )
      );
      return;
    }

    let reservation;
    try {
      reservation = await reserveInferenceRequest(pool, {
        organizationId: ctx.organizationId,
        userId: ctx.userId,
        deviceId: ctx.deviceId,
        operationId: envelope.operationId,
        idempotencyKey,
        retryOf: envelope.retryOf ?? null,
        mode: envelope.mode,
        requestedAction: envelope.task.requestedAction,
        route: ROUTE,
        promptVersion: PROMPT_VERSION
      });
    } catch (err) {
      if (err instanceof QuotaExceededError) {
        sendError(reply, err);
        return;
      }
      throw err;
    }

    const requestId = reservation.requestId;

    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });
    const send = (event: InferenceStreamEvent): void => {
      reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };

    send({ type: "request.accepted", requestId });

    if (reservation.reused) {
      // Idempotency-Key replay of a request we already know about — never
      // call the provider again (inference-stream.md "Retry and idempotency
      // rules"). Only a completed/failed/cancelled replay has anything
      // further to report; a still-in-flight one (another connection is
      // handling it) just closes here.
      if (reservation.state === "completed") {
        send({ type: "completed", requestId, promptVersion: PROMPT_VERSION });
      } else if (reservation.state === "failed" || reservation.state === "cancelled") {
        send({ type: "error", code: "INTERNAL_ERROR", message: "This operation already ended.", requestId });
      }
      reply.raw.end();
      return;
    }

    // A mutable ref, not a bare `let` — it's written from the "close"
    // listener below as well as the main flow, and a plain `let` reads as
    // provably-always-false to static analysis that can't see the listener
    // might have already fired by the time a given `await` resumes.
    const lifecycle = { terminated: false };
    request.raw.on("close", () => {
      if (!lifecycle.terminated) {
        lifecycle.terminated = true;
        void releaseInferenceRequest(pool, ctx.organizationId, requestId, "cancelled");
      }
    });

    try {
      await transitionState(pool, ctx.organizationId, requestId, "running");

      send({
        type: "decision",
        intent: "grammar",
        confidence: null,
        outputMode: envelope.task.outputModeHint,
        route: ROUTE,
        reasonCode: null
      });

      const { deltas, usage } = provider.fixGrammar(envelope.content.draft);
      let streamingStarted = false;
      for await (const delta of deltas) {
        if (lifecycle.terminated) break;
        if (!streamingStarted) {
          streamingStarted = true;
          await transitionState(pool, ctx.organizationId, requestId, "streaming");
        }
        send({ type: "output.delta", delta });
      }
      if (lifecycle.terminated) return;

      const result = await usage;
      const commitResult = await commitInferenceRequest(pool, {
        organizationId: ctx.organizationId,
        userId: ctx.userId,
        requestId,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens
      });
      lifecycle.terminated = true;

      send({ type: "usage.summary", usedUnits: commitResult.usedUnits, remainingUnits: commitResult.remainingUnits });
      send({ type: "completed", requestId, promptVersion: PROMPT_VERSION });
    } catch (err) {
      if (!lifecycle.terminated) {
        lifecycle.terminated = true;
        request.log.error({ err: { message: (err as Error).message } }, "inference/stream failed");
        await releaseInferenceRequest(pool, ctx.organizationId, requestId, "failed");
        send({ type: "error", code: "INTERNAL_ERROR", message: "Something went wrong. Please try again.", requestId });
      }
    } finally {
      reply.raw.end();
    }
  });
}

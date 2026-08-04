import type { FastifyInstance } from "fastify";
import type pg from "pg";
import {
  InferenceRequestEnvelopeSchema,
  type DecisionIntent,
  type InferenceStreamEvent,
  type LogicalRoute,
  type WritingAction
} from "@writerflow/shared";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { ApiError, sendError } from "../errors.js";
import { commitInferenceRequest, releaseInferenceRequest, reserveInferenceRequest, transitionState } from "../inference/accounting.js";
import type { InferenceProvider } from "../inference/provider.js";

const actionConfig: Record<WritingAction, { route: LogicalRoute; promptVersion: string; intent: DecisionIntent }> = {
  elaborate: { route: "rewrite_standard", promptVersion: "elaborate@5.1.0", intent: "elaborate" },
  formal: { route: "rewrite_standard", promptVersion: "formal@5.1.0", intent: "tone" },
  casual: { route: "rewrite_standard", promptVersion: "casual@5.1.0", intent: "tone" },
  fixGrammar: { route: "grammar_fast", promptVersion: "grammar@5.1.0", intent: "grammar" },
  reply: { route: "rewrite_standard", promptVersion: "reply@5.1.0", intent: "reply" },
  custom: { route: "rewrite_standard", promptVersion: "custom@5.1.0", intent: "custom" },
  promptBuilder: { route: "prompt_enhancer", promptVersion: "prompt-builder@5.1.0", intent: "prompt_enhance" }
};

/**
 * POST /v2/inference/stream — Docs/contracts/inference-stream.md. The first
 * explicit writing action endpoint. Every code path — happy stream, quota
 * exceeded, provider error, client disconnect — commits or releases the
 * reservation created up front; none may leave one dangling.
 */
export function registerInferenceRoutes(app: FastifyInstance, pool: pg.Pool, keys: SigningKeyProvider, provider: InferenceProvider): void {
  app.post("/inference/stream", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);

    const idempotencyKey = request.headers["idempotency-key"];
    const clientVersion = request.headers["x-writerflow-version"];
    const clientDevice = request.headers["x-writerflow-device"];
    if (
      typeof idempotencyKey !== "string"
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey)
    ) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Idempotency-Key header must be a UUID."));
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
    const action = envelope.task.requestedAction;
    if (!action) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "requestedAction is required."));
      return;
    }
    const config = actionConfig[action];

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
        requestedAction: action,
        route: config.route,
        promptVersion: config.promptVersion
      });
    } catch (err) {
      if (err instanceof ApiError) {
        sendError(reply, err);
        return;
      }
      throw err;
    }

    const requestId = reservation.requestId;
    request.log.info({
      event: reservation.reused ? "inference.replay" : "inference.accepted",
      inferenceRequestId: requestId,
      route: config.route
    });

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
        send({ type: "completed", requestId, promptVersion: config.promptVersion });
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
    const providerAbort = new AbortController();
        // Cold starts + MI token can take a couple seconds; fail closed after
        // that so the Mac spinner cannot hang forever on silent reasoning.
        const FIRST_DELTA_TIMEOUT_MS = 15_000;
    let firstDeltaTimer: ReturnType<typeof setTimeout> | undefined;
    const providerStartedAt = Date.now();
    const keepalive = setInterval(() => {
      if (!lifecycle.terminated) reply.raw.write(": keepalive\n\n");
    }, 15_000);
    request.raw.on("close", () => {
      if (!lifecycle.terminated) {
        lifecycle.terminated = true;
        clearInterval(keepalive);
        if (firstDeltaTimer) clearTimeout(firstDeltaTimer);
        providerAbort.abort();
        request.log.warn({
          event: "inference.sse_disconnect",
          inferenceRequestId: requestId,
          route: config.route
        });
        void releaseInferenceRequest(pool, ctx.organizationId, requestId, "cancelled");
      }
    });

    try {
      await transitionState(pool, ctx.organizationId, requestId, "running");

      send({
        type: "decision",
        intent: config.intent,
        confidence: null,
        outputMode: envelope.task.outputModeHint,
        route: config.route,
        reasonCode: null
      });

      const { deltas, usage } = provider.stream({
        action,
        route: config.route,
        envelope,
        signal: providerAbort.signal
      });
      let streamingStarted = false;
      firstDeltaTimer = setTimeout(() => {
        if (!lifecycle.terminated && !streamingStarted) {
          request.log.warn({
            event: "inference.first_delta_timeout",
            inferenceRequestId: requestId,
            route: config.route,
            timeoutMs: FIRST_DELTA_TIMEOUT_MS
          });
          providerAbort.abort();
        }
      }, FIRST_DELTA_TIMEOUT_MS);
      for await (const delta of deltas) {
        if (lifecycle.terminated) break;
        if (!streamingStarted) {
          streamingStarted = true;
          clearTimeout(firstDeltaTimer);
          await transitionState(pool, ctx.organizationId, requestId, "streaming");
          request.log.info({
            event: "inference.first_delta",
            inferenceRequestId: requestId,
            route: config.route,
            latencyMs: Date.now() - providerStartedAt
          });
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
      send({ type: "completed", requestId, promptVersion: config.promptVersion });
      request.log.info({
        event: "inference.completed",
        inferenceRequestId: requestId,
        route: config.route
      });
    } catch (err) {
      if (!lifecycle.terminated) {
        lifecycle.terminated = true;
        const aborted = providerAbort.signal.aborted;
        const apiError = err instanceof ApiError ? err : null;
        const message = err instanceof Error ? err.message : String(err);
        const looksRateLimited =
          apiError?.code === "RATE_LIMITED"
          || /\(429[,)]/.test(message)
          || /rate.?limit|quota|capacity/i.test(message);
        request.log.error({
          err: { message, code: apiError?.code },
          aborted,
          rateLimited: looksRateLimited,
          event: looksRateLimited
            ? "inference.provider_rate_limited"
            : aborted
              ? "inference.first_delta_timeout"
              : "inference.provider_failed",
          inferenceRequestId: requestId,
          route: config.route,
          latencyMs: Date.now() - providerStartedAt
        }, "inference/stream failed");
        await releaseInferenceRequest(pool, ctx.organizationId, requestId, "failed");
        if (apiError) {
          send({
            type: "error",
            code: apiError.code,
            message: apiError.message,
            requestId
          });
        } else if (looksRateLimited) {
          send({
            type: "error",
            code: "RATE_LIMITED",
            message: "The writing model is at capacity. Please try again in a moment.",
            requestId
          });
        } else {
          send({
            type: "error",
            code: aborted ? "MODEL_UNAVAILABLE" : "INTERNAL_ERROR",
            message: aborted
              ? "WriterFlow took too long to start writing — the model may be overloaded. Please try again."
              : "Something went wrong. Please try again.",
            requestId
          });
        }
      }
    } finally {
      if (firstDeltaTimer) clearTimeout(firstDeltaTimer);
      clearInterval(keepalive);
      reply.raw.end();
    }
  });
}

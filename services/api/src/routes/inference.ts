import type { FastifyInstance } from "fastify";
import type pg from "pg";
import {
  InferenceRequestEnvelopeSchema,
  type DecisionIntent,
  type InferenceRequestEnvelope,
  type InferenceStreamEvent,
  type LogicalRoute,
  type SkillId,
  type WritingAction
} from "@writerflow/shared";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { ApiError, sendError } from "../errors.js";
import {
  commitInferenceRequest,
  recordProviderStageUsage,
  releaseInferenceRequest,
  reserveInferenceRequest,
  transitionState,
  updateInferenceDecision,
  updateShadowInferenceDecision
} from "../inference/accounting.js";
import type { InferenceProvider } from "../inference/provider.js";
import type { PromptCompiler } from "../inference/promptCompiler.js";
import { SkillOrchestrator, type SkillDecision } from "../inference/skillOrchestrator.js";

const actionConfig: Record<WritingAction, { route: LogicalRoute; intent: DecisionIntent }> = {
  elaborate: { route: "rewrite_standard", intent: "elaborate" },
  formal: { route: "rewrite_standard", intent: "tone" },
  casual: { route: "rewrite_standard", intent: "tone" },
  fixGrammar: { route: "grammar_fast", intent: "grammar" },
  reply: { route: "rewrite_standard", intent: "reply" },
  custom: { route: "rewrite_standard", intent: "custom" },
  promptBuilder: { route: "prompt_enhancer", intent: "prompt_enhance" }
};

const skillIntent: Readonly<Record<SkillId, DecisionIntent>> = {
  reply: "reply",
  continue: "reply",
  improve: "improve",
  correct: "grammar",
  shorten: "improve",
  expand: "elaborate",
  tone_adapt: "tone",
  prompt_enhance: "prompt_enhance",
  custom_adjust: "custom"
};

interface ResolvedRun {
  action: WritingAction;
  route: LogicalRoute;
  intent: DecisionIntent;
  outputMode: "replace" | "insert_before";
  promptVersion: string;
  envelope: InferenceRequestEnvelope;
  skill?: SkillDecision;
  maxOutputTokens?: number;
}

function shadowAutoEnvelope(envelope: Extract<InferenceRequestEnvelope, { mode: "explicit" }>): InferenceRequestEnvelope {
  return {
    operationId: envelope.operationId,
    retryOf: envelope.retryOf,
    mode: "auto",
    task: { outputModeHint: envelope.task.outputModeHint },
    target: envelope.target,
    content: envelope.content,
    signals: envelope.signals,
    personalization: envelope.personalization
  };
}

function requestContentTooLarge(body: unknown): boolean {
  if (body == null || typeof body !== "object") return false;
  const root = body as Record<string, unknown>;
  const content = root["content"];
  const task = root["task"];
  const contentRecord = content != null && typeof content === "object" ? content as Record<string, unknown> : {};
  const taskRecord = task != null && typeof task === "object" ? task as Record<string, unknown> : {};
  return (typeof contentRecord["draft"] === "string" && contentRecord["draft"].length > 8_000)
    || (typeof contentRecord["selectedText"] === "string" && contentRecord["selectedText"].length > 8_000)
    || (typeof contentRecord["conversation"] === "string" && contentRecord["conversation"].length > 16_000)
    || (typeof taskRecord["instruction"] === "string" && taskRecord["instruction"].length > 2_000)
    || (typeof taskRecord["priorOutput"] === "string" && taskRecord["priorOutput"].length > 8_000);
}

/** One explicit-trigger operation. Auto classification is internal to this SSE request. */
export function registerInferenceRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider,
  provider: InferenceProvider,
  promptCompiler: PromptCompiler
): void {
  const orchestrator = SkillOrchestrator.load(provider);

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

    if (requestContentTooLarge(request.body)) {
      sendError(reply, new ApiError("TARGET_TOO_LARGE", 413, "The writing context is too large for one request."));
      return;
    }
    const parsed = InferenceRequestEnvelopeSchema.safeParse(request.body);
    if (!parsed.success) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Request body failed schema validation."));
      return;
    }
    const envelope = parsed.data;
    if (
      envelope.mode !== "explicit"
      && !["1", "true"].includes(process.env["WRITERFLOW_COHORT_AUTO_ACTION"] ?? "")
    ) {
      sendError(reply, new ApiError("MODEL_UNAVAILABLE", 503, "Automatic writing is not enabled for this cohort."));
      return;
    }
    const explicitAction = envelope.mode === "explicit" ? envelope.task.requestedAction : null;
    if (envelope.mode === "explicit" && !explicitAction) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "requestedAction is required."));
      return;
    }
    const provisionalRoute = explicitAction ? actionConfig[explicitAction].route : "rewrite_standard";
    const provisionalPromptVersion = explicitAction
      ? promptCompiler.promptVersion(explicitAction)
      : "skills@pending";

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
        requestedAction: explicitAction ?? null,
        route: provisionalRoute,
        promptVersion: provisionalPromptVersion,
        decisionSource: explicitAction ? "explicit" : null,
        executionMode: explicitAction ? "direct" : null,
        parentOperationId: envelope.mode === "adjust" ? envelope.task.parentOperationId : null
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
      route: provisionalRoute,
      mode: envelope.mode
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
      if (reservation.state === "completed") {
        send({ type: "completed", requestId, promptVersion: provisionalPromptVersion });
      } else if (reservation.state === "failed" || reservation.state === "cancelled") {
        send({ type: "error", code: "INTERNAL_ERROR", message: "This operation already ended.", requestId });
      }
      reply.raw.end();
      return;
    }

    const lifecycle = { terminated: false };
    const providerAbort = new AbortController();
    const FIRST_DELTA_TIMEOUT_MS = 2_500;
    let firstDeltaTimer: ReturnType<typeof setTimeout> | undefined;
    let resolvedRoute: LogicalRoute = provisionalRoute;
    let generatorAttempted = false;
    let generatorCommitted = false;
    let generatorUsage: Promise<{ inputTokens: number; outputTokens: number }> | undefined;
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
        request.log.warn({ event: "inference.sse_disconnect", inferenceRequestId: requestId, route: resolvedRoute });
        void releaseInferenceRequest(pool, ctx.organizationId, requestId, "cancelled");
      }
    });

    try {
      await transitionState(pool, ctx.organizationId, requestId, "running");
      const shadowPromise = envelope.mode === "explicit"
        && ["1", "true"].includes(process.env["WRITERFLOW_SHADOW_AUTO_DECISIONS"] ?? "")
        ? orchestrator.prepare(shadowAutoEnvelope(envelope), providerAbort.signal)
        : undefined;
      let streamingStarted = false;
      firstDeltaTimer = setTimeout(() => {
        if (!lifecycle.terminated && !streamingStarted) {
          request.log.warn({
            event: "inference.first_delta_timeout",
            inferenceRequestId: requestId,
            route: resolvedRoute,
            timeoutMs: FIRST_DELTA_TIMEOUT_MS
          });
          providerAbort.abort();
        }
      }, FIRST_DELTA_TIMEOUT_MS);

      let resolved: ResolvedRun;
      if (envelope.mode === "explicit") {
        const action = envelope.task.requestedAction;
        if (!action) throw new ApiError("VALIDATION_FAILED", 400, "requestedAction is required.");
        const config = actionConfig[action];
        resolved = {
          action,
          route: config.route,
          intent: config.intent,
          outputMode: envelope.task.outputModeHint,
          promptVersion: promptCompiler.promptVersion(action),
          envelope
        };
      } else {
        const prepared = await orchestrator.prepare(envelope, providerAbort.signal);
        const decision = prepared.decision;
        resolved = {
          action: decision.manifest.action,
          route: decision.manifest.route,
          intent: skillIntent[decision.manifest.id],
          outputMode: prepared.providerEnvelope.task.outputModeHint,
          promptVersion: decision.manifest.version,
          envelope: prepared.providerEnvelope,
          skill: decision,
          maxOutputTokens: decision.manifest.maxOutputTokens
        };
        await updateInferenceDecision(pool, {
          organizationId: ctx.organizationId,
          requestId,
          requestedAction: resolved.action,
          route: resolved.route,
          promptVersion: resolved.promptVersion,
          skillId: decision.manifest.id,
          skillVersion: decision.manifest.version,
          decisionSource: decision.source,
          confidence: decision.confidence,
          executionMode: decision.executionMode
        });
        for (const stage of prepared.usages) {
          await recordProviderStageUsage(pool, {
            organizationId: ctx.organizationId,
            userId: ctx.userId,
            requestId,
            stage: stage.stage,
            stageKey: stage.stageKey,
            attemptNo: stage.attemptNo,
            route: stage.route,
            inputTokens: stage.usage.inputTokens,
            outputTokens: stage.usage.outputTokens,
            status: stage.status
          });
        }
      }
      resolvedRoute = resolved.route;
      if (providerAbort.signal.aborted) {
        throw new ApiError("MODEL_UNAVAILABLE", 503, "WriterFlow took too long to start writing. Please try again.");
      }

      send({
        type: "decision",
        intent: resolved.intent,
        confidence: resolved.skill?.confidence ?? null,
        outputMode: resolved.outputMode,
        route: resolved.route,
        reasonCode: resolved.skill?.reasonCode ?? null,
        ...(resolved.skill ? {
          skillId: resolved.skill.manifest.id,
          skillVersion: resolved.skill.manifest.version,
          skillLabel: resolved.skill.manifest.label,
          decisionSource: resolved.skill.source,
          executionMode: resolved.skill.executionMode
        } : {
          decisionSource: "explicit" as const,
          executionMode: "direct" as const
        })
      });

      const providerRequest = {
        action: resolved.action,
        route: resolved.route,
        envelope: resolved.envelope,
        signal: providerAbort.signal,
        ...(resolved.skill ? { skillId: resolved.skill.manifest.id } : {}),
        ...(resolved.maxOutputTokens ? { maxCompletionTokensOverride: resolved.maxOutputTokens } : {})
      };
      generatorAttempted = true;
      const { deltas, usage } = provider.stream(providerRequest);
      generatorUsage = usage;
      for await (const delta of deltas) {
        if (lifecycle.terminated) break;
        if (delta.length === 0) continue;
        if (!streamingStarted) {
          streamingStarted = true;
          clearTimeout(firstDeltaTimer);
          await transitionState(pool, ctx.organizationId, requestId, "streaming");
          request.log.info({
            event: "inference.first_delta",
            inferenceRequestId: requestId,
            route: resolved.route,
            executionMode: resolved.skill?.executionMode ?? "direct",
            latencyMs: Date.now() - providerStartedAt
          });
        }
        send({ type: "output.delta", delta });
      }
      if (lifecycle.terminated) return;
      if (!streamingStarted) {
        throw new ApiError("MODEL_UNAVAILABLE", 503, "WriterFlow returned no text. Please try again.");
      }

      const result = await usage;
      if (shadowPromise) {
        const shadow = await shadowPromise;
        await updateShadowInferenceDecision(pool, {
          organizationId: ctx.organizationId,
          requestId,
          skillId: shadow.decision.manifest.id,
          skillVersion: shadow.decision.manifest.version,
          confidence: shadow.decision.confidence,
          reasonCode: shadow.decision.reasonCode
        });
        for (const stage of shadow.usages) {
          await recordProviderStageUsage(pool, {
            organizationId: ctx.organizationId,
            userId: ctx.userId,
            requestId,
            stage: stage.stage,
            stageKey: `shadow_${stage.stageKey}`,
            attemptNo: stage.attemptNo,
            route: stage.route,
            inputTokens: stage.usage.inputTokens,
            outputTokens: stage.usage.outputTokens,
            status: stage.status
          });
        }
      }
      const commitResult = await commitInferenceRequest(pool, {
        organizationId: ctx.organizationId,
        userId: ctx.userId,
        requestId,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens
      });
      generatorCommitted = true;
      lifecycle.terminated = true;
      send({ type: "usage.summary", usedUnits: commitResult.usedUnits, remainingUnits: commitResult.remainingUnits });
      send({ type: "completed", requestId, promptVersion: resolved.promptVersion });
      request.log.info({ event: "inference.completed", inferenceRequestId: requestId, route: resolved.route });
    } catch (err) {
      if (!lifecycle.terminated) {
        lifecycle.terminated = true;
        if (generatorAttempted && !generatorCommitted) {
          const failedUsage = generatorUsage
            ? await Promise.race([
                generatorUsage.catch(() => ({ inputTokens: 0, outputTokens: 0 })),
                new Promise<{ inputTokens: number; outputTokens: number }>((resolve) => {
                  setTimeout(() => { resolve({ inputTokens: 0, outputTokens: 0 }); }, 100);
                })
              ])
            : { inputTokens: 0, outputTokens: 0 };
          try {
            await recordProviderStageUsage(pool, {
              organizationId: ctx.organizationId,
              userId: ctx.userId,
              requestId,
              stage: "generator",
              stageKey: "generator",
              attemptNo: 1,
              route: resolvedRoute,
              inputTokens: failedUsage.inputTokens,
              outputTokens: failedUsage.outputTokens,
              status: "failed"
            });
          } catch {
            request.log.error({ event: "inference.generator_usage_record_failed", inferenceRequestId: requestId });
          }
        }
        const aborted = providerAbort.signal.aborted;
        const apiError = err instanceof ApiError ? err : null;
        const message = err instanceof Error ? err.message : String(err);
        const looksRateLimited = apiError?.code === "RATE_LIMITED"
          || /\(429[,]?\)|rate.?limit|quota|capacity/i.test(message);
        request.log.error({
          err: { message, code: apiError?.code },
          aborted,
          rateLimited: looksRateLimited,
          event: looksRateLimited ? "inference.provider_rate_limited" : aborted
            ? "inference.first_delta_timeout" : "inference.provider_failed",
          inferenceRequestId: requestId,
          route: resolvedRoute,
          latencyMs: Date.now() - providerStartedAt
        }, "inference/stream failed");
        await releaseInferenceRequest(pool, ctx.organizationId, requestId, "failed");
        if (apiError) {
          send({ type: "error", code: apiError.code, message: apiError.message, requestId });
        } else if (looksRateLimited) {
          send({ type: "error", code: "RATE_LIMITED", message: "The writing model is at capacity. Please try again in a moment.", requestId });
        } else {
          send({
            type: "error",
            code: aborted ? "MODEL_UNAVAILABLE" : "INTERNAL_ERROR",
            message: aborted
              ? "WriterFlow took too long to start writing. Please try again."
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

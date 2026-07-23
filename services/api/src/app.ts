import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import { timingSafeEqual } from "node:crypto";
import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import { FORBIDDEN_LOG_FIELD_NAMES } from "@writerflow/shared";
import type pg from "pg";
import type { AppConfig } from "./config.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerDeviceRoutes } from "./routes/device.js";
import { registerJwksRoutes } from "./routes/jwks.js";
import { registerWebSessionRoutes } from "./routes/webSession.js";
import { registerWebAccountRoutes } from "./routes/webAccount.js";
import { registerAccountRoutes } from "./routes/account.js";
import { registerUsageRoutes } from "./routes/usage.js";
import { registerBillingRoutes } from "./routes/billing.js";
import { registerClassifierRoutes } from "./routes/classifier.js";
import { registerCohortRoutes } from "./routes/cohort.js";
import { registerInferenceRoutes } from "./routes/inference.js";
import { ApiError, sendError, type ErrorBody } from "./errors.js";
import type { SigningKeyProvider } from "./jwt/keys.js";
import type { EntraIdTokenVerifier } from "./entra/verifier.js";
import type { InferenceProvider } from "./inference/provider.js";
import { DevEchoProvider } from "./inference/devEchoProvider.js";

export interface AppDependencies {
  config: AppConfig;
  pool: pg.Pool;
  signingKeys: SigningKeyProvider;
  /** null when ENTRA_* env vars are unset — no tenant exists yet (cloud apply pending). */
  entraVerifier: EntraIdTokenVerifier | null;
  /** Stage 5.4: defaults to DevEchoProvider (below) until a real Azure
   * OpenAI resource exists (cloud apply pending, blocked on user cost
   * approval). Optional so existing callers/tests that don't touch
   * inference routes don't need to know this dependency exists. */
  inferenceProvider?: InferenceProvider;
  /** Test-only seam: capture log output instead of writing to stdout. */
  logStream?: NodeJS.WritableStream;
}

/**
 * Redact paths cover every current + potential future body/header location a
 * forbidden field (Docs/contracts/inference-stream.md "Allowed log fields")
 * could land in Fastify's default request-completion log line. This is
 * defense-in-depth: routes must never pass forbidden fields to `request.log`
 * in the first place (services/shared's toSafeInferenceLogFields is the
 * primary control for structured operation logs).
 */
function buildRedactPaths(): string[] {
  const paths = [
    "req.headers.authorization",
    "req.headers.cookie",
    "req.headers.x-writerflow-origin",
    "res.headers.set-cookie"
  ];
  for (const field of FORBIDDEN_LOG_FIELD_NAMES) {
    paths.push(`req.body.${field}`);
    paths.push(`req.body.task.${field}`);
    paths.push(`req.body.content.${field}`);
    paths.push(`req.body.personalization.${field}`);
    paths.push(`req.body.task.promptBuilder.${field}`);
  }
  return paths;
}

export function buildApp(deps: AppDependencies): FastifyInstance {
  const app = Fastify({
    logger: {
      level: deps.config.LOG_LEVEL,
      redact: {
        paths: buildRedactPaths(),
        censor: "[redacted]"
      },
      ...(deps.logStream ? { stream: deps.logStream } : {})
    },
    trustProxy: true
  });

  app.addHook("onRequest", async (request, reply) => {
    const expectedSecret = deps.config.APIM_ORIGIN_SECRET;
    if (!expectedSecret || !request.raw.url?.startsWith("/v2/")) return;

    const suppliedSecret = request.headers["x-writerflow-origin"];
    const expected = Buffer.from(expectedSecret);
    const supplied = Buffer.from(typeof suppliedSecret === "string" ? suppliedSecret : "");
    if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) {
      await reply.code(403).send({
        code: "FORBIDDEN",
        message: "This API route is available only through the WriterFlow gateway.",
        requestId: request.id
      });
    }
  });

  void app.register(sensible);
  // Only the website ever calls this API from a browser (/web-session/token,
  // /device/approve, per V2-ARCHITECTURE.md §5.1 step 3) — the Mac app uses
  // URLSession, which isn't subject to CORS at all. One exact origin, no
  // wildcard, matching the same non-wildcard-audience discipline used
  // everywhere else in this service.
  void app.register(cors, { origin: deps.config.WEBSITE_BASE_URL });
  registerHealthRoutes(app, deps.pool);
  registerJwksRoutes(app, deps.signingKeys);
  registerDeviceRoutes(app, deps.pool, deps.signingKeys, deps.config.WEBSITE_BASE_URL);
  registerWebSessionRoutes(app, deps.signingKeys, deps.entraVerifier, deps.pool, deps.config);
  registerWebAccountRoutes(app, deps.signingKeys, deps.entraVerifier, deps.pool, deps.config);
  registerAccountRoutes(app, deps.pool, deps.signingKeys);
  registerUsageRoutes(app, deps.pool, deps.signingKeys);
  registerBillingRoutes(app, deps.pool, deps.signingKeys, deps.config);
  registerClassifierRoutes(app, deps.pool, deps.signingKeys);
  registerCohortRoutes(app, deps.pool, deps.signingKeys, deps.config);
  registerInferenceRoutes(app, deps.pool, deps.signingKeys, deps.inferenceProvider ?? new DevEchoProvider());

  app.setErrorHandler((error: FastifyError | ApiError, request, reply) => {
    if (error instanceof ApiError) {
      request.log.error({ err: { message: error.message, code: error.code } });
      sendError(reply, error);
      return;
    }
    request.log.error({ err: { message: error.message, code: error.code } });
    const statusCode = error.statusCode ?? 500;
    const body: ErrorBody = {
      code: statusCode >= 500 ? "INTERNAL_ERROR" : "VALIDATION_FAILED",
      message: statusCode >= 500 ? "Something went wrong. Please try again." : error.message,
      requestId: request.id
    };
    reply.code(statusCode).send(body);
  });

  return app;
}

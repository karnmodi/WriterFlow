import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import sensible from "@fastify/sensible";
import { FORBIDDEN_LOG_FIELD_NAMES } from "@writerflow/shared";
import type pg from "pg";
import type { AppConfig } from "./config.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerDeviceRoutes } from "./routes/device.js";
import { registerJwksRoutes } from "./routes/jwks.js";
import { registerWebSessionRoutes } from "./routes/webSession.js";
import { ApiError, sendError, type ErrorBody } from "./errors.js";
import type { SigningKeyProvider } from "./jwt/keys.js";
import type { EntraIdTokenVerifier } from "./entra/verifier.js";

export interface AppDependencies {
  config: AppConfig;
  pool: pg.Pool;
  signingKeys: SigningKeyProvider;
  /** null when ENTRA_* env vars are unset — no tenant exists yet (cloud apply pending). */
  entraVerifier: EntraIdTokenVerifier | null;
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
  const paths = ["req.headers.authorization"];
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
      }
    },
    trustProxy: true
  });

  void app.register(sensible);
  registerHealthRoutes(app, deps.pool);
  registerJwksRoutes(app, deps.signingKeys);
  registerDeviceRoutes(app, deps.pool, deps.signingKeys, deps.config.WEBSITE_BASE_URL);
  registerWebSessionRoutes(app, deps.signingKeys, deps.entraVerifier);

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

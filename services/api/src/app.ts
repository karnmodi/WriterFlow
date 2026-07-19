import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import sensible from "@fastify/sensible";
import { FORBIDDEN_LOG_FIELD_NAMES } from "@writerflow/shared";
import type pg from "pg";
import type { AppConfig } from "./config.js";
import { registerHealthRoutes } from "./routes/health.js";

export interface AppDependencies {
  config: AppConfig;
  pool: pg.Pool;
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

  app.setErrorHandler((error: FastifyError, request, reply) => {
    request.log.error({ err: { message: error.message, code: error.code } });
    const statusCode = error.statusCode ?? 500;
    reply.code(statusCode).send({
      error: {
        code: statusCode >= 500 ? "INTERNAL_ERROR" : "VALIDATION_FAILED",
        message: statusCode >= 500 ? "Something went wrong. Please try again." : error.message
      }
    });
  });

  return app;
}

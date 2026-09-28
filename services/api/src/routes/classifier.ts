import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { ApiError, sendError } from "../errors.js";
import type { AppConfig } from "../config.js";

/**
 * Local/eval-only compatibility endpoint. Production classification is
 * deliberately internal to POST /inference/stream so the Mac never makes a
 * separate content-bearing classifier request.
 */
export function registerClassifierRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider,
  config: AppConfig
): void {
  app.post("/classifier/evaluate", async (request, reply) => {
    await requireDeviceAuth(request, pool, keys);
    if (config.NODE_ENV === "production") {
      sendError(reply, new ApiError("VALIDATION_FAILED", 404, "Not found."));
      return;
    }
    sendError(
      reply,
      new ApiError("INTERNAL_ERROR", 501, "Use the local Phase 6 evaluation harness for classifier scoring.")
    );
  });
}

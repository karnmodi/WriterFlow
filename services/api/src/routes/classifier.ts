import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { ApiError, sendError } from "../errors.js";

/**
 * Phase 6 classifier endpoint scaffold. Returns structured not-implemented
 * until the server classifier model and eval harness pass thresholds.
 */
export function registerClassifierRoutes(app: FastifyInstance, pool: pg.Pool, keys: SigningKeyProvider): void {
  app.post("/classifier/evaluate", async (request, reply) => {
    await requireDeviceAuth(request, pool, keys);
    sendError(
      reply,
      new ApiError("INTERNAL_ERROR", 501, "Server classifier is not enabled yet — Phase 6 Stage 6.3.")
    );
  });
}

import type { FastifyInstance } from "fastify";
import type { AppConfig } from "../config.js";
import type pg from "pg";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";

export interface CohortFlags {
  useCloudInference: boolean;
  allowByoFallback: boolean;
  autoActionEnabled: boolean;
  classifierEnabled: boolean;
  composedEnabled: boolean;
}

/** Server-controlled transport + Phase 6 rollout kill switches. */
export function resolveCohortFlags(_config: AppConfig): CohortFlags {
  const env = process.env["WRITERFLOW_COHORT_CLOUD_INFERENCE"];
  const useCloudInference = env === "1" || env === "true";
  const fallbackEnv = process.env["WRITERFLOW_COHORT_BYO_FALLBACK"];
  const allowByoFallback = fallbackEnv !== "0" && fallbackEnv !== "false";
  const autoActionEnabled = ["1", "true"].includes(process.env["WRITERFLOW_COHORT_AUTO_ACTION"] ?? "");
  const classifierEnabled = ["1", "true"].includes(process.env["WRITERFLOW_CLASSIFIER_ENABLED"] ?? "");
  const composedEnabled = ["1", "true"].includes(process.env["WRITERFLOW_COMPOSED_ENABLED"] ?? "");
  return { useCloudInference, allowByoFallback, autoActionEnabled, classifierEnabled, composedEnabled };
}

/** GET /v2/cohort/flags — Mac app reads server-controlled transport switches. */
export function registerCohortRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider,
  config: AppConfig
): void {
  app.get("/cohort/flags", async (request, reply) => {
    await requireDeviceAuth(request, pool, keys);
    reply.code(200).send(resolveCohortFlags(config));
  });
}

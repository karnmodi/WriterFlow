import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { getCurrentUsage } from "../account/usage.js";

/** GET /v2/usage/current — Docs/contracts/openapi.yaml UsageCurrent. */
export function registerUsageRoutes(app: FastifyInstance, pool: pg.Pool, keys: SigningKeyProvider): void {
  app.get("/usage/current", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);
    const usage = await getCurrentUsage(pool, ctx.organizationId);
    reply.code(200).send(usage);
  });
}

import type { FastifyInstance } from "fastify";
import type pg from "pg";

/**
 * Liveness/readiness only — never discloses secrets, dependency hostnames, or
 * error detail (Stage 5.1 "Add container health/readiness endpoints that
 * disclose no secrets or dependency details").
 */
export function registerHealthRoutes(app: FastifyInstance, pool: pg.Pool): void {
  app.get("/healthz", () => ({ status: "ok" }));

  app.get("/readyz", async (_request, reply) => {
    try {
      await pool.query("SELECT 1");
      return { status: "ready" };
    } catch {
      return reply.code(503).send({ status: "not_ready" });
    }
  });
}

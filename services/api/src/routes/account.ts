import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { ApiError, sendError } from "../errors.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { requireDeviceAuth } from "../auth/guard.js";
import { getAccountSnapshot, revokeDevice } from "../account/service.js";

/**
 * Docs/contracts/openapi.yaml GET /me and DELETE /devices/{id} — the first
 * two routes that require a full WriterFlow device access token (not the
 * bearer-exempt pairing routes, not the web-session token). Both go through
 * requireDeviceAuth, which re-checks devices.revoked_at and users.status on
 * every call, not just at token-mint time.
 */
export function registerAccountRoutes(app: FastifyInstance, pool: pg.Pool, keys: SigningKeyProvider): void {
  app.get("/me", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);
    const snapshot = await getAccountSnapshot(pool, ctx);
    if (!snapshot) {
      // The authenticated device itself vanished between token mint and now
      // (shouldn't happen — requireDeviceAuth just confirmed it exists —
      // but the DB is the source of truth, not the assumption).
      sendError(reply, new ApiError("DEVICE_REVOKED", 401, "This device has been signed out. Please pair again."));
      return;
    }
    reply.code(200).send(snapshot);
  });

  app.delete<{ Params: { id: string } }>("/devices/:id", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);
    const result = await revokeDevice(pool, ctx, request.params.id);
    if (result === "not_found") {
      sendError(reply, new ApiError("VALIDATION_FAILED", 404, "Device does not belong to the calling user."));
      return;
    }
    reply.code(204).send();
  });
}

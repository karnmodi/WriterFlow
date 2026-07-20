import type pg from "pg";
import type { FastifyRequest } from "fastify";
import { verifyAccessToken } from "../jwt/issuer.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { withTenantContext } from "../db.js";
import { ApiError } from "../errors.js";

export interface AuthenticatedDeviceRequest {
  userId: string;
  deviceId: string;
  organizationId: string;
}

/**
 * Shared guard for every route that requires a WriterFlow device access
 * token (V2-ARCHITECTURE.md §5.2: "Every authenticated request rejects
 * disabled user, inactive membership, and revoked device before business
 * work"). Verifies the token itself, then re-checks `devices.revoked_at`
 * and `users.status` against the database on every call — a signature check
 * alone only proves the token was validly minted, not that the device/user
 * are still in good standing since then (a device can be revoked or a user
 * disabled after a token was issued but before it expires).
 *
 * Throws `ApiError` (never returns a rejection value) so route handlers can
 * just `await requireDeviceAuth(...)` and let the shared error handler
 * (services/api/src/app.ts) format the response.
 */
export async function requireDeviceAuth(
  request: FastifyRequest,
  pool: pg.Pool,
  keys: SigningKeyProvider
): Promise<AuthenticatedDeviceRequest> {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    throw new ApiError("AUTH_REQUIRED", 401, "Sign in required.");
  }
  const token = authHeader.slice("Bearer ".length);
  const verified = await verifyAccessToken(keys, token);
  if (!verified.ok) {
    throw new ApiError("AUTH_INVALID", 401, "Invalid or expired token.");
  }
  const { sub: userId, device_id: deviceId, org_id: organizationId } = verified.claims;

  const standing = await withTenantContext(pool, organizationId, async (client) => {
    const deviceResult = await client.query<{ revoked_at: Date | null }>(
      `SELECT revoked_at FROM devices WHERE id = $1`,
      [deviceId]
    );
    const userResult = await client.query<{ status: string }>(`SELECT status FROM users WHERE id = $1`, [userId]);
    return {
      device: deviceResult.rows[0],
      user: userResult.rows[0]
    };
  });

  if (!standing.device || standing.device.revoked_at) {
    throw new ApiError("DEVICE_REVOKED", 401, "This device has been signed out. Please pair again.");
  }
  if (!standing.user || standing.user.status !== "active") {
    throw new ApiError("AUTH_INVALID", 403, "This account is disabled.");
  }

  return { userId, deviceId, organizationId };
}

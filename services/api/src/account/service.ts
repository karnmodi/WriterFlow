import type pg from "pg";
import { withTenantContext } from "../db.js";
import type { AuthenticatedDeviceRequest } from "../auth/guard.js";
import { type AccountSnapshot, buildSnapshot, readEntitlementSnapshot, readUserDisplayInfo } from "../pairing/snapshot.js";
import { readMonthlyUnitsUsed } from "./usage.js";

/** GET /v2/me — Docs/contracts/openapi.yaml. */
export async function getAccountSnapshot(db: pg.Pool, ctx: AuthenticatedDeviceRequest): Promise<AccountSnapshot | null> {
  return withTenantContext(db, ctx.organizationId, async (client) => {
    const deviceResult = await client.query<{
      label: string | null;
      created_at: Date;
      last_seen_at: Date | null;
      revoked_at: Date | null;
    }>(`SELECT install_metadata->>'label' AS label, created_at, last_seen_at, revoked_at FROM devices WHERE id = $1`, [
      ctx.deviceId
    ]);
    const device = deviceResult.rows[0];
    if (!device) return null;

    const privacy = await client.query<{ sync_enabled: boolean; consent_version: number }>(
      `SELECT sync_enabled, consent_version FROM privacy_preferences WHERE user_id = $1`,
      [ctx.userId]
    );
    const entitlement = await readEntitlementSnapshot(client, ctx.organizationId);
    const monthlyUnitsUsed = await readMonthlyUnitsUsed(client, ctx.organizationId);
    const display = await readUserDisplayInfo(client, ctx.userId);

    return buildSnapshot(
      ctx.userId,
      ctx.organizationId,
      ctx.deviceId,
      device.label,
      device.created_at,
      entitlement,
      privacy.rows[0],
      device.last_seen_at ?? undefined,
      device.revoked_at != null,
      display,
      monthlyUnitsUsed
    );
  });
}

export type RevokeDeviceResult = "revoked" | "not_found";

/**
 * DELETE /v2/devices/{id} — Docs/contracts/openapi.yaml: 404 "Device does
 * not belong to the calling user" if the id doesn't resolve to one of the
 * authenticated user's own devices (RLS already scopes by organization;
 * this adds the explicit per-user ownership check the spec calls for, ready
 * for when an organization can have more than one member). Also revokes any
 * still-active refresh-token family for that device, not just future access
 * tokens — a stolen refresh token stops working immediately, not just once
 * its short-lived access token expires.
 */
export async function revokeDevice(
  db: pg.Pool,
  ctx: AuthenticatedDeviceRequest,
  targetDeviceId: string
): Promise<RevokeDeviceResult> {
  return withTenantContext(db, ctx.organizationId, async (client) => {
    const result = await client.query(
      `UPDATE devices SET revoked_at = now()
       WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
       RETURNING id`,
      [targetDeviceId, ctx.userId]
    );
    if (result.rowCount === 0) {
      // Either unknown, already revoked, or belongs to someone else — the
      // spec's 404 case treats all of these the same to callers.
      const exists = await client.query(`SELECT 1 FROM devices WHERE id = $1 AND user_id = $2`, [
        targetDeviceId,
        ctx.userId
      ]);
      if ((exists.rowCount ?? 0) === 0) return "not_found";
      // Already revoked — idempotent success, not an error.
    }
    await client.query(
      `UPDATE refresh_tokens SET revoked_at = now() WHERE device_id = $1 AND revoked_at IS NULL`,
      [targetDeviceId]
    );
    return "revoked";
  });
}

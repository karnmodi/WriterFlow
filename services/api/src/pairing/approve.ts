import type pg from "pg";
import type { EntraIdentity } from "../entra/verifier.js";
import { withDeviceBootstrapLookup, withTenantContext } from "../db.js";
import { resolveOrLinkUserFromEntra } from "../account/identity.js";
import {
  type AccountSnapshot,
  buildSnapshot,
  readEntitlementSnapshot,
  readUserDisplayInfo
} from "./snapshot.js";
import { readMonthlyUnitsUsed } from "../account/usage.js";

export type ApproveDeviceResult =
  | { kind: "approved"; snapshot: AccountSnapshot }
  | { kind: "invalid_user_code" }
  | { kind: "account_disabled" };

/**
 * POST /v2/device/approve's provisioning logic — Docs/contracts/openapi.yaml,
 * V2-ARCHITECTURE.md §5.2. User identity is resolved/linked via
 * `resolveOrLinkUserFromEntra` (`services/api/src/account/identity.ts`); a
 * fresh device_code always gets a new `devices` row. Re-approving an
 * already-approved user_code returns the same snapshot without a second
 * device row.
 */
export async function approveDevice(
  db: pg.Pool,
  identity: EntraIdentity,
  userCode: string
): Promise<ApproveDeviceResult> {
  const authRow = await db.query<{
    id: string;
    status: string;
    approved_device_id: string | null;
    expires_at: Date;
    device_label: string | null;
  }>(
    `SELECT id, status, approved_device_id, expires_at, device_label FROM device_authorizations WHERE user_code = $1`,
    [userCode]
  );
  const auth = authRow.rows[0];
  if (!auth) return { kind: "invalid_user_code" };

  if (auth.status === "approved" && auth.approved_device_id) {
    const existing = await fetchSnapshotForDevice(db, auth.approved_device_id);
    return existing ? { kind: "approved", snapshot: existing } : { kind: "invalid_user_code" };
  }
  if (auth.status !== "pending" || new Date(auth.expires_at) < new Date()) {
    return { kind: "invalid_user_code" };
  }

  const resolved = await resolveOrLinkUserFromEntra(db, identity);
  if (resolved.kind === "disabled") return { kind: "account_disabled" };

  const snapshot = await provisionDeviceForExistingUser(
    db,
    identity,
    resolved.userId,
    resolved.organizationId,
    auth.id,
    auth.device_label
  );
  return { kind: "approved", snapshot };
}

async function provisionDeviceForExistingUser(
  db: pg.Pool,
  identity: EntraIdentity,
  userId: string,
  organizationId: string,
  deviceAuthorizationId: string,
  deviceLabel: string | null
): Promise<AccountSnapshot> {
  return withTenantContext(db, organizationId, async (client) => {
    const deviceResult = await client.query<{ id: string; created_at: Date }>(
      `INSERT INTO devices (user_id, organization_id, install_metadata) VALUES ($1, $2, $3::jsonb) RETURNING id, created_at`,
      [userId, organizationId, JSON.stringify(deviceLabel ? { label: deviceLabel } : {})]
    );
    const device = deviceResult.rows[0];
    if (!device) throw new Error("failed to insert device");
    await client.query(
      `UPDATE device_authorizations SET status = 'approved', approved_device_id = $1, approved_at = now() WHERE id = $2`,
      [device.id, deviceAuthorizationId]
    );
    const privacy = await client.query<{ sync_enabled: boolean; consent_version: number }>(
      `SELECT sync_enabled, consent_version FROM privacy_preferences WHERE user_id = $1`,
      [userId]
    );
    const entitlement = await readEntitlementSnapshot(client, organizationId);
    const monthlyUnitsUsed = await readMonthlyUnitsUsed(client, organizationId);
    await client.query(`UPDATE auth_identities SET display_claims = $3::jsonb WHERE issuer = $1 AND subject = $2`, [
      identity.issuer,
      identity.subject,
      JSON.stringify(identity.displayClaims)
    ]);
    const display = { displayName: identity.displayName, email: identity.email };
    return buildSnapshot(userId, organizationId, device.id, deviceLabel, device.created_at, entitlement, privacy.rows[0], undefined, false, display, monthlyUnitsUsed);
  });
}

async function fetchSnapshotForDevice(db: pg.Pool, deviceId: string): Promise<AccountSnapshot | null> {
  return withDeviceBootstrapLookup(db, async (client) => {
    const deviceResult = await client.query<{
      id: string;
      user_id: string;
      organization_id: string;
      created_at: Date;
      label: string | null;
    }>(
      `SELECT id, user_id, organization_id, created_at, install_metadata->>'label' AS label FROM devices WHERE id = $1`,
      [deviceId]
    );
    const device = deviceResult.rows[0];
    if (!device) return null;
    const entitlement = await readEntitlementSnapshot(client, device.organization_id);
    const monthlyUnitsUsed = await readMonthlyUnitsUsed(client, device.organization_id);
    const privacy = await client.query<{ sync_enabled: boolean; consent_version: number }>(
      `SELECT sync_enabled, consent_version FROM privacy_preferences WHERE user_id = $1`,
      [device.user_id]
    );
    const display = await readUserDisplayInfo(client, device.user_id);
    return buildSnapshot(
      device.user_id,
      device.organization_id,
      device.id,
      device.label,
      device.created_at,
      entitlement,
      privacy.rows[0],
      undefined,
      false,
      display,
      monthlyUnitsUsed
    );
  });
}

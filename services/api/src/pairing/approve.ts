import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { EntraIdentity } from "../entra/verifier.js";
import { withDeviceBootstrapLookup, withTenantContext } from "../db.js";
import { type AccountSnapshot, FREE_ALPHA_MONTHLY_UNITS, buildSnapshot, readEntitlementSnapshot } from "./snapshot.js";

export type ApproveDeviceResult =
  | { kind: "approved"; snapshot: AccountSnapshot }
  | { kind: "invalid_user_code" }
  | { kind: "account_disabled" };

function isUniqueViolation(err: unknown): boolean {
  return typeof err === "object" && err !== null && "code" in err && (err as { code?: string }).code === "23505";
}

/**
 * POST /v2/device/approve's provisioning logic — Docs/contracts/openapi.yaml,
 * V2-ARCHITECTURE.md §5.2. Idempotent on (issuer, subject): a returning
 * identity gets its existing user/organization; a fresh device_code always
 * gets a new `devices` row bound to it. Re-approving an already-approved
 * user_code (e.g. a client retry) returns the same snapshot without a
 * second device row.
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

  const existingUser = await db.query<{ id: string; primary_organization_id: string | null; status: string }>(
    `SELECT au.user_id AS id, u.primary_organization_id, u.status
     FROM auth_identities au JOIN users u ON u.id = au.user_id
     WHERE au.issuer = $1 AND au.subject = $2`,
    [identity.issuer, identity.subject]
  );
  const existing = existingUser.rows[0];

  if (existing && existing.status !== "active") {
    return { kind: "account_disabled" };
  }

  if (existing?.primary_organization_id) {
    const snapshot = await provisionDeviceForExistingUser(
      db,
      existing.id,
      existing.primary_organization_id,
      auth.id,
      auth.device_label
    );
    return { kind: "approved", snapshot };
  }

  try {
    const snapshot = await provisionNewUser(db, identity, auth.id, auth.device_label);
    return { kind: "approved", snapshot };
  } catch (err) {
    if (!isUniqueViolation(err)) throw err;
    // Lost the race to a concurrent approve for the same identity — fall
    // back to the existing-user path now that it must exist.
    const retry = await db.query<{ id: string; primary_organization_id: string | null }>(
      `SELECT au.user_id AS id, u.primary_organization_id
       FROM auth_identities au JOIN users u ON u.id = au.user_id
       WHERE au.issuer = $1 AND au.subject = $2`,
      [identity.issuer, identity.subject]
    );
    const row = retry.rows[0];
    if (!row?.primary_organization_id) throw err;
    return {
      kind: "approved",
      snapshot: await provisionDeviceForExistingUser(db, row.id, row.primary_organization_id, auth.id, auth.device_label)
    };
  }
}

async function provisionDeviceForExistingUser(
  db: pg.Pool,
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
    return buildSnapshot(userId, organizationId, device.id, deviceLabel, device.created_at, entitlement, privacy.rows[0]);
  });
}

async function provisionNewUser(
  db: pg.Pool,
  identity: EntraIdentity,
  deviceAuthorizationId: string,
  deviceLabel: string | null
): Promise<AccountSnapshot> {
  const userId = randomUUID();
  const organizationId = randomUUID();
  return withTenantContext(db, organizationId, async (client) => {
    await client.query(`INSERT INTO users (id, status) VALUES ($1, 'active')`, [userId]);
    await client.query(`INSERT INTO auth_identities (user_id, issuer, subject) VALUES ($1, $2, $3)`, [
      userId,
      identity.issuer,
      identity.subject
    ]);
    await client.query(`INSERT INTO organizations (id, kind, owner_user_id) VALUES ($1, 'personal', $2)`, [
      organizationId,
      userId
    ]);
    await client.query(
      `INSERT INTO organization_memberships (organization_id, user_id, role) VALUES ($1, $2, 'owner')`,
      [organizationId, userId]
    );
    await client.query(`UPDATE users SET primary_organization_id = $1 WHERE id = $2`, [organizationId, userId]);
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
    await client.query(
      `INSERT INTO privacy_preferences (user_id, organization_id) VALUES ($1, $2)`,
      [userId, organizationId]
    );
    await client.query(
      `INSERT INTO entitlement_grants (organization_id, source, feature_key, limit_value)
       VALUES ($1, 'free_alpha', 'monthly_units', $2::jsonb)`,
      [organizationId, JSON.stringify({ units: FREE_ALPHA_MONTHLY_UNITS })]
    );
    await client.query(
      `INSERT INTO entitlement_projection (organization_id, features) VALUES ($1, $2::jsonb)`,
      [organizationId, JSON.stringify({ monthly_units_included: FREE_ALPHA_MONTHLY_UNITS })]
    );
    return buildSnapshot(userId, organizationId, device.id, deviceLabel, device.created_at, {
      units: FREE_ALPHA_MONTHLY_UNITS
    });
  });
}

async function fetchSnapshotForDevice(db: pg.Pool, deviceId: string): Promise<AccountSnapshot | null> {
  // Bare device-ID lookup, same bootstrap problem as pollDeviceToken —
  // reuse the same escape hatch rather than inventing a second one.
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
    const privacy = await client.query<{ sync_enabled: boolean; consent_version: number }>(
      `SELECT sync_enabled, consent_version FROM privacy_preferences WHERE user_id = $1`,
      [device.user_id]
    );
    return buildSnapshot(
      device.user_id,
      device.organization_id,
      device.id,
      device.label,
      device.created_at,
      entitlement,
      privacy.rows[0]
    );
  });
}

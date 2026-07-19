import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { EntraIdentity } from "../entra/verifier.js";
import { withDeviceBootstrapLookup, withTenantContext } from "../db.js";

export interface DeviceSnapshot {
  id: string;
  label: string | null;
  createdAt: string;
  lastUsedAt: string;
  revoked: boolean;
  current: true;
}

export interface EntitlementSnapshot {
  plan: "free" | "pro";
  monthlyUnitsIncluded: number;
  monthlyUnitsUsed: number;
  features: string[];
}

export interface PrivacyPreferencesSnapshot {
  personalizationSyncEnabled: boolean;
  consentVersion: string;
}

export interface AccountSnapshot {
  userId: string;
  organizationId: string;
  device: DeviceSnapshot;
  entitlement: EntitlementSnapshot;
  privacy: PrivacyPreferencesSnapshot;
}

export type ApproveDeviceResult =
  | { kind: "approved"; snapshot: AccountSnapshot }
  | { kind: "invalid_user_code" }
  | { kind: "account_disabled" };

const FREE_ALPHA_MONTHLY_UNITS = 500;

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
  }>(
    `SELECT id, status, approved_device_id, expires_at FROM device_authorizations WHERE user_code = $1`,
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
      auth.id
    );
    return { kind: "approved", snapshot };
  }

  try {
    const snapshot = await provisionNewUser(db, identity, auth.id);
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
    return { kind: "approved", snapshot: await provisionDeviceForExistingUser(db, row.id, row.primary_organization_id, auth.id) };
  }
}

async function provisionDeviceForExistingUser(
  db: pg.Pool,
  userId: string,
  organizationId: string,
  deviceAuthorizationId: string
): Promise<AccountSnapshot> {
  return withTenantContext(db, organizationId, async (client) => {
    const deviceResult = await client.query<{ id: string; created_at: Date }>(
      `INSERT INTO devices (user_id, organization_id) VALUES ($1, $2) RETURNING id, created_at`,
      [userId, organizationId]
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
    return buildSnapshot(userId, organizationId, device.id, null, device.created_at, entitlement, privacy.rows[0]);
  });
}

async function provisionNewUser(
  db: pg.Pool,
  identity: EntraIdentity,
  deviceAuthorizationId: string
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
      `INSERT INTO devices (user_id, organization_id) VALUES ($1, $2) RETURNING id, created_at`,
      [userId, organizationId]
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
    return buildSnapshot(userId, organizationId, device.id, null, device.created_at, {
      units: FREE_ALPHA_MONTHLY_UNITS
    });
  });
}

async function readEntitlementSnapshot(
  client: pg.PoolClient,
  organizationId: string
): Promise<{ units: number }> {
  const result = await client.query<{ features: { monthly_units_included?: number } }>(
    `SELECT features FROM entitlement_projection WHERE organization_id = $1`,
    [organizationId]
  );
  const units = result.rows[0]?.features.monthly_units_included ?? FREE_ALPHA_MONTHLY_UNITS;
  return { units };
}

function buildSnapshot(
  userId: string,
  organizationId: string,
  deviceId: string,
  deviceLabel: string | null,
  createdAt: Date,
  entitlementUnits: { units: number },
  privacy?: { sync_enabled: boolean; consent_version: number }
): AccountSnapshot {
  return {
    userId,
    organizationId,
    device: {
      id: deviceId,
      label: deviceLabel,
      createdAt: createdAt.toISOString(),
      lastUsedAt: createdAt.toISOString(),
      revoked: false,
      current: true
    },
    entitlement: {
      plan: "free",
      monthlyUnitsIncluded: entitlementUnits.units,
      monthlyUnitsUsed: 0,
      features: ["auto_write"]
    },
    privacy: {
      personalizationSyncEnabled: privacy?.sync_enabled ?? false,
      consentVersion: String(privacy?.consent_version ?? 1)
    }
  };
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
    }>(`SELECT id, user_id, organization_id, created_at FROM devices WHERE id = $1`, [deviceId]);
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
      null,
      device.created_at,
      entitlement,
      privacy.rows[0]
    );
  });
}

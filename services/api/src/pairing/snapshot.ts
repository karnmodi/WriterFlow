import type pg from "pg";

/** Docs/contracts/openapi.yaml AccountSnapshot and its nested schemas — shared by /device/approve and GET /me. */

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

export const FREE_ALPHA_MONTHLY_UNITS = 500;

export async function readEntitlementSnapshot(client: pg.PoolClient, organizationId: string): Promise<{ units: number }> {
  const result = await client.query<{ features: { monthly_units_included?: number } }>(
    `SELECT features FROM entitlement_projection WHERE organization_id = $1`,
    [organizationId]
  );
  const units = result.rows[0]?.features.monthly_units_included ?? FREE_ALPHA_MONTHLY_UNITS;
  return { units };
}

export function buildSnapshot(
  userId: string,
  organizationId: string,
  deviceId: string,
  deviceLabel: string | null,
  createdAt: Date,
  entitlementUnits: { units: number },
  privacy?: { sync_enabled: boolean; consent_version: number },
  lastUsedAt?: Date,
  revoked = false
): AccountSnapshot {
  return {
    userId,
    organizationId,
    device: {
      id: deviceId,
      label: deviceLabel,
      createdAt: createdAt.toISOString(),
      lastUsedAt: (lastUsedAt ?? createdAt).toISOString(),
      revoked,
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

import type pg from "pg";
import { displayFromStoredClaims } from "../entra/verifier.js";

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
  displayName: string | null;
  email: string | null;
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
  revoked = false,
  display?: { displayName: string | null; email: string | null },
  monthlyUnitsUsed = 0
): AccountSnapshot {
  return {
    userId,
    organizationId,
    displayName: display?.displayName ?? null,
    email: display?.email ?? null,
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
      monthlyUnitsUsed,
      features: ["auto_write"]
    },
    privacy: {
      personalizationSyncEnabled: privacy?.sync_enabled ?? false,
      consentVersion: String(privacy?.consent_version ?? 1)
    }
  };
}

export async function readUserDisplayInfo(
  client: pg.PoolClient,
  userId: string
): Promise<{ displayName: string | null; email: string | null }> {
  const result = await client.query<{ display_claims: unknown }>(
    `SELECT display_claims FROM auth_identities WHERE user_id = $1 LIMIT 1`,
    [userId]
  );
  return displayFromStoredClaims(result.rows[0]?.display_claims);
}

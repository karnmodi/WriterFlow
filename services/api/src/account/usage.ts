import type pg from "pg";
import { withTenantContext } from "../db.js";
import { FREE_ALPHA_MONTHLY_UNITS, readEntitlementSnapshot } from "../pairing/snapshot.js";

export interface UsageCurrent {
  monthlyUnitsIncluded: number;
  monthlyUnitsUsed: number;
  resetAt: string;
}

function currentPeriod(now = new Date()): { start: string; end: Date } {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return { start: start.toISOString().slice(0, 10), end };
}

/** Read used units from usage_balances for the current calendar month. */
export async function readMonthlyUnitsUsed(
  client: pg.PoolClient,
  organizationId: string
): Promise<number> {
  const { start } = currentPeriod();
  const result = await client.query<{ used_units: number }>(
    `SELECT used_units FROM usage_balances WHERE organization_id = $1 AND period_start = $2`,
    [organizationId, start]
  );
  return result.rows[0]?.used_units ?? 0;
}

export async function getCurrentUsage(db: pg.Pool, organizationId: string): Promise<UsageCurrent> {
  return withTenantContext(db, organizationId, async (client) => {
    const entitlement = await readEntitlementSnapshot(client, organizationId);
    const used = await readMonthlyUnitsUsed(client, organizationId);
    const { end } = currentPeriod();
    return {
      monthlyUnitsIncluded: entitlement.units,
      monthlyUnitsUsed: used,
      resetAt: end.toISOString()
    };
  });
}

/** Used by /me and /web/me snapshot builders. */
export async function readUsageForSnapshot(
  client: pg.PoolClient,
  organizationId: string
): Promise<{ included: number; used: number }> {
  const entitlement = await readEntitlementSnapshot(client, organizationId);
  const used = await readMonthlyUnitsUsed(client, organizationId);
  return { included: entitlement.units || FREE_ALPHA_MONTHLY_UNITS, used };
}

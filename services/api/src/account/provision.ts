import type pg from "pg";
import type { EntraIdentity } from "../entra/verifier.js";
import { withTenantContext } from "../db.js";
import { readEntitlementSnapshot, readUserDisplayInfo } from "../pairing/snapshot.js";
import { readMonthlyUnitsUsed } from "./usage.js";
import { resolveOrLinkUserFromEntra } from "./identity.js";

export type EnsureUserResult =
  | { kind: "active"; userId: string; organizationId: string; created: boolean }
  | { kind: "disabled" };

/**
 * Provisions or resolves a WriterFlow user + personal org from an Entra identity
 * without creating a device. Used by POST /web-account/token (ADR-0013).
 * Identity persistence (including Microsoft ↔ email OTP linking) lives in
 * `resolveOrLinkUserFromEntra` — `services/api/src/account/identity.ts`.
 */
export async function ensureUserFromEntra(db: pg.Pool, identity: EntraIdentity): Promise<EnsureUserResult> {
  const resolved = await resolveOrLinkUserFromEntra(db, identity);
  if (resolved.kind === "disabled") return { kind: "disabled" };
  return {
    kind: "active",
    userId: resolved.userId,
    organizationId: resolved.organizationId,
    created: resolved.created
  };
}

export interface WebAccountSnapshot {
  userId: string;
  organizationId: string;
  displayName: string | null;
  email: string | null;
  entitlement: {
    plan: "free" | "pro";
    monthlyUnitsIncluded: number;
    monthlyUnitsUsed: number;
    features: string[];
  };
  privacy: {
    personalizationSyncEnabled: boolean;
    consentVersion: string;
  };
}

/** GET /web/me — account snapshot for the website (no device row). */
export async function getWebAccountSnapshot(
  db: pg.Pool,
  userId: string,
  organizationId: string
): Promise<WebAccountSnapshot | null> {
  return withTenantContext(db, organizationId, async (client) => {
    const userResult = await client.query<{ status: string }>(`SELECT status FROM users WHERE id = $1`, [userId]);
    if (!userResult.rows[0] || userResult.rows[0].status !== "active") return null;

    const privacy = await client.query<{ sync_enabled: boolean; consent_version: number }>(
      `SELECT sync_enabled, consent_version FROM privacy_preferences WHERE user_id = $1`,
      [userId]
    );
    const entitlement = await readEntitlementSnapshot(client, organizationId);
    const monthlyUnitsUsed = await readMonthlyUnitsUsed(client, organizationId);
    const display = await readUserDisplayInfo(client, userId);

    return {
      userId,
      organizationId,
      displayName: display.displayName,
      email: display.email,
      entitlement: {
        plan: "free",
        monthlyUnitsIncluded: entitlement.units,
        monthlyUnitsUsed,
        features: ["auto_write"]
      },
      privacy: {
        personalizationSyncEnabled: privacy.rows[0]?.sync_enabled ?? false,
        consentVersion: String(privacy.rows[0]?.consent_version ?? 1)
      }
    };
  });
}

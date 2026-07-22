import type pg from "pg";
import type { EntraIdentity } from "./verifier.js";

/** Upserts display_claims for an existing auth_identities row — no-op if none yet. */
export async function updateDisplayClaimsIfExists(db: pg.Pool | pg.PoolClient, identity: EntraIdentity): Promise<void> {
  await db.query(
    `UPDATE auth_identities SET display_claims = $3::jsonb WHERE issuer = $1 AND subject = $2`,
    [identity.issuer, identity.subject, JSON.stringify(identity.displayClaims)]
  );
}

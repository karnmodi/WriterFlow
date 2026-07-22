import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { EntraIdentity } from "../entra/verifier.js";
import { withTenantContext } from "../db.js";
import { FREE_ALPHA_MONTHLY_UNITS } from "../pairing/snapshot.js";

export type ResolvedUser =
  | { kind: "active"; userId: string; organizationId: string; created: boolean; linked: boolean }
  | { kind: "disabled" };

function isUniqueViolation(err: unknown): boolean {
  return typeof err === "object" && err !== null && "code" in err && (err as { code?: string }).code === "23505";
}

function normalizedEmail(identity: EntraIdentity): string | null {
  const email = identity.email?.trim() || identity.displayClaims.email?.trim();
  if (!email || !email.includes("@")) return null;
  return email.toLowerCase();
}

/**
 * Identity persistence for Entra sign-in (ADR-0001 / ADR-0013).
 *
 * Primary key remains `(issuer, subject)` — never email alone.
 * When Entra returns a *new* subject for the same verified email under the
 * same issuer (typical when Microsoft social and email OTP coexist without
 * Entra-side account linking collapsing them to one `sub`), we attach the
 * new `(issuer, subject)` row to the existing WriterFlow user so OTP and
 * Microsoft both land on one account and re-auth is never blocked.
 */
export async function resolveOrLinkUserFromEntra(db: pg.Pool, identity: EntraIdentity): Promise<ResolvedUser> {
  const bySubject = await lookupByIssuerSubject(db, identity.issuer, identity.subject);
  if (bySubject) {
    if (bySubject.status !== "active") return { kind: "disabled" };
    if (!bySubject.primary_organization_id) throw new Error("active user missing primary organization");
    await upsertIdentityClaims(db, identity, bySubject.id);
    return {
      kind: "active",
      userId: bySubject.id,
      organizationId: bySubject.primary_organization_id,
      created: false,
      linked: false
    };
  }

  const email = normalizedEmail(identity);
  if (email) {
    const byEmail = await lookupByIssuerEmail(db, identity.issuer, email);
    if (byEmail) {
      if (byEmail.status !== "active") return { kind: "disabled" };
      if (!byEmail.primary_organization_id) throw new Error("active user missing primary organization");
      await linkSubjectToUser(db, identity, byEmail.id);
      return {
        kind: "active",
        userId: byEmail.id,
        organizationId: byEmail.primary_organization_id,
        created: false,
        linked: true
      };
    }
  }

  try {
    const created = await provisionNewUser(db, identity);
    return { kind: "active", ...created, created: true, linked: false };
  } catch (err) {
    if (!isUniqueViolation(err)) throw err;
    const retry = await lookupByIssuerSubject(db, identity.issuer, identity.subject);
    if (!retry?.primary_organization_id) throw err;
    if (retry.status !== "active") return { kind: "disabled" };
    await upsertIdentityClaims(db, identity, retry.id);
    return {
      kind: "active",
      userId: retry.id,
      organizationId: retry.primary_organization_id,
      created: false,
      linked: false
    };
  }
}

async function lookupByIssuerSubject(
  db: pg.Pool,
  issuer: string,
  subject: string
): Promise<{ id: string; primary_organization_id: string | null; status: string } | undefined> {
  const result = await db.query<{ id: string; primary_organization_id: string | null; status: string }>(
    `SELECT au.user_id AS id, u.primary_organization_id, u.status
     FROM auth_identities au JOIN users u ON u.id = au.user_id
     WHERE au.issuer = $1 AND au.subject = $2`,
    [issuer, subject]
  );
  return result.rows[0];
}

async function lookupByIssuerEmail(
  db: pg.Pool,
  issuer: string,
  emailLower: string
): Promise<{ id: string; primary_organization_id: string | null; status: string } | undefined> {
  // Same Entra issuer only — email is a linking hint within one tenant, not a global join key.
  const result = await db.query<{ id: string; primary_organization_id: string | null; status: string }>(
    `SELECT au.user_id AS id, u.primary_organization_id, u.status
     FROM auth_identities au JOIN users u ON u.id = au.user_id
     WHERE au.issuer = $1
       AND lower(coalesce(au.display_claims->>'email', '')) = $2
     ORDER BY au.created_at ASC
     LIMIT 1`,
    [issuer, emailLower]
  );
  return result.rows[0];
}

async function linkSubjectToUser(db: pg.Pool, identity: EntraIdentity, userId: string): Promise<void> {
  await db.query(
    `INSERT INTO auth_identities (user_id, issuer, subject, display_claims)
     VALUES ($1, $2, $3, $4::jsonb)
     ON CONFLICT (issuer, subject) DO UPDATE SET display_claims = EXCLUDED.display_claims`,
    [userId, identity.issuer, identity.subject, JSON.stringify(identity.displayClaims)]
  );
}

async function upsertIdentityClaims(db: pg.Pool, identity: EntraIdentity, userId: string): Promise<void> {
  await db.query(
    `INSERT INTO auth_identities (user_id, issuer, subject, display_claims)
     VALUES ($1, $2, $3, $4::jsonb)
     ON CONFLICT (issuer, subject) DO UPDATE SET display_claims = EXCLUDED.display_claims`,
    [userId, identity.issuer, identity.subject, JSON.stringify(identity.displayClaims)]
  );
}

async function provisionNewUser(
  db: pg.Pool,
  identity: EntraIdentity
): Promise<{ userId: string; organizationId: string }> {
  const userId = randomUUID();
  const organizationId = randomUUID();
  return withTenantContext(db, organizationId, async (client) => {
    await client.query(`INSERT INTO users (id, status) VALUES ($1, 'active')`, [userId]);
    await client.query(`INSERT INTO auth_identities (user_id, issuer, subject, display_claims) VALUES ($1, $2, $3, $4::jsonb)`, [
      userId,
      identity.issuer,
      identity.subject,
      JSON.stringify(identity.displayClaims)
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
    await client.query(`INSERT INTO privacy_preferences (user_id, organization_id) VALUES ($1, $2)`, [
      userId,
      organizationId
    ]);
    await client.query(
      `INSERT INTO entitlement_grants (organization_id, source, feature_key, limit_value)
       VALUES ($1, 'free_alpha', 'monthly_units', $2::jsonb)`,
      [organizationId, JSON.stringify({ units: FREE_ALPHA_MONTHLY_UNITS })]
    );
    await client.query(
      `INSERT INTO entitlement_projection (organization_id, features) VALUES ($1, $2::jsonb)`,
      [organizationId, JSON.stringify({ monthly_units_included: FREE_ALPHA_MONTHLY_UNITS })]
    );
    return { userId, organizationId };
  });
}

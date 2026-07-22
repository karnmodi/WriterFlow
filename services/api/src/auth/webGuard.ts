import type pg from "pg";
import type { FastifyRequest } from "fastify";
import { verifyWebAccountToken } from "../jwt/issuer.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { withTenantContext } from "../db.js";
import { ApiError } from "../errors.js";

export interface AuthenticatedWebAccountRequest {
  userId: string;
  organizationId: string;
  entraIssuer: string;
  entraSubject: string;
}

/** Guard for website account routes (ADR-0013). */
export async function requireWebAccountAuth(
  request: FastifyRequest,
  pool: pg.Pool,
  keys: SigningKeyProvider
): Promise<AuthenticatedWebAccountRequest> {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    throw new ApiError("AUTH_REQUIRED", 401, "Sign in required.");
  }
  const token = authHeader.slice("Bearer ".length);
  const verified = await verifyWebAccountToken(keys, token);
  if (!verified.ok) {
    throw new ApiError("AUTH_INVALID", 401, "Invalid or expired token.");
  }
  const { sub: userId, org_id: organizationId, entra_issuer: entraIssuer, entra_subject: entraSubject } =
    verified.claims;

  const standing = await withTenantContext(pool, organizationId, async (client) => {
    const userResult = await client.query<{ status: string }>(`SELECT status FROM users WHERE id = $1`, [userId]);
    return userResult.rows[0];
  });

  if (!standing || standing.status !== "active") {
    throw new ApiError("AUTH_INVALID", 403, "This account is disabled.");
  }

  return { userId, organizationId, entraIssuer, entraSubject };
}

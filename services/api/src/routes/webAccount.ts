import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { ApiError, sendError } from "../errors.js";
import type pg from "pg";
import type { AppConfig } from "../config.js";
import type { EntraIdTokenVerifier } from "../entra/verifier.js";
import { updateDisplayClaimsIfExists } from "../entra/displayClaims.js";
import { enrichIdentityFromUserInfo } from "../entra/userInfo.js";
import { isPlaceholderDisplayName } from "../entra/claims.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import {
  mintWebAccountToken,
  mintWebSessionBridgeFromAccount,
  verifyWebAccountToken
} from "../jwt/issuer.js";
import { ensureUserFromEntra, getWebAccountSnapshot } from "../account/provision.js";
import { requireWebAccountAuth } from "../auth/webGuard.js";

const WebAccountTokenRequestSchema = z.strictObject({
  idToken: z.string().min(1),
  accessToken: z.string().min(1).optional()
});

/**
 * ADR-0013 website account session routes — POST /web-account/token,
 * GET /web/me, POST /web-session/bridge.
 */
export function registerWebAccountRoutes(
  app: FastifyInstance,
  keys: SigningKeyProvider,
  entraVerifier: EntraIdTokenVerifier | null,
  pool: pg.Pool,
  config: AppConfig
): void {
  app.post("/web-account/token", async (request, reply) => {
    if (!entraVerifier) {
      throw new ApiError(
        "INTERNAL_ERROR",
        503,
        "Web account issuance is not configured on this environment."
      );
    }
    const parsed = WebAccountTokenRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid web account token request.");
    }

    const result = await entraVerifier.verify(parsed.data.idToken);
    if (!result.ok) {
      throw new ApiError("AUTH_INVALID", 401, "Invalid Entra ID token.");
    }

    let identity = result.identity;
    if (
      parsed.data.accessToken &&
      (!identity.displayName ||
        isPlaceholderDisplayName(identity.displayName) ||
        !identity.email ||
        !identity.displayClaims.given_name)
    ) {
      identity = await enrichIdentityFromUserInfo(
        identity,
        parsed.data.accessToken,
        entraVerifier.issuer,
        config.ENTRA_USERINFO_URI
      );
    }

    await updateDisplayClaimsIfExists(pool, identity);
    const ensured = await ensureUserFromEntra(pool, identity);
    if (ensured.kind === "disabled") {
      throw new ApiError("AUTH_INVALID", 403, "This account is disabled.");
    }

    const { token, expiresIn } = await mintWebAccountToken(keys, {
      userId: ensured.userId,
      organizationId: ensured.organizationId,
      entraIssuer: identity.issuer,
      entraSubject: identity.subject,
      displayClaims: identity.displayClaims
    });
    reply.code(200).send({ accessToken: token, expiresIn, created: ensured.created });
  });

  app.get("/web/me", async (request, reply) => {
    const ctx = await requireWebAccountAuth(request, pool, keys);
    const snapshot = await getWebAccountSnapshot(pool, ctx.userId, ctx.organizationId);
    if (!snapshot) {
      sendError(reply, new ApiError("AUTH_INVALID", 403, "This account is disabled."));
      return;
    }
    reply.code(200).send(snapshot);
  });

  app.post("/web-session/bridge", async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      throw new ApiError("AUTH_REQUIRED", 401, "Sign in required.");
    }
    const verified = await verifyWebAccountToken(keys, authHeader.slice("Bearer ".length));
    if (!verified.ok) {
      throw new ApiError("AUTH_INVALID", 401, "Invalid or expired token.");
    }
    const { token, expiresIn } = await mintWebSessionBridgeFromAccount(keys, verified.claims);
    reply.code(200).send({ accessToken: token, expiresIn });
  });
}

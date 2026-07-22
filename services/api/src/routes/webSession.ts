import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { ApiError } from "../errors.js";
import type pg from "pg";
import type { AppConfig } from "../config.js";
import type { EntraIdTokenVerifier } from "../entra/verifier.js";
import { updateDisplayClaimsIfExists } from "../entra/displayClaims.js";
import { enrichIdentityFromUserInfo } from "../entra/userInfo.js";
import { isPlaceholderDisplayName } from "../entra/claims.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { mintWebSessionToken } from "../jwt/issuer.js";

const WebSessionTokenRequestSchema = z.strictObject({
  idToken: z.string().min(1),
  accessToken: z.string().min(1).optional()
});

/**
 * POST /v2/web-session/token — Stage 5.2's "second token issuer" answer to
 * /device/approve's open design question (phases/phase-5-v2-cloud-
 * foundation.md). Called by the website's server-side code, never the Mac
 * app, immediately after it independently validates the user's Entra ID
 * token. This endpoint validates that same token a second time (its own
 * EntraIdTokenVerifier, not the website's say-so) and, only if valid, mints
 * a short-lived WriterFlow web-session token scoped to calling
 * /device/approve — never a device access token.
 */
export function registerWebSessionRoutes(
  app: FastifyInstance,
  keys: SigningKeyProvider,
  entraVerifier: EntraIdTokenVerifier | null,
  pool: pg.Pool,
  config: AppConfig
): void {
  app.post("/web-session/token", async (request, reply) => {
    if (!entraVerifier) {
      throw new ApiError(
        "INTERNAL_ERROR",
        503,
        "Web session issuance is not configured on this environment."
      );
    }
    const parsed = WebSessionTokenRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid web session token request.");
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
    const { token, expiresIn } = await mintWebSessionToken(keys, {
      entraIssuer: identity.issuer,
      entraSubject: identity.subject,
      displayClaims: identity.displayClaims
    });
    reply.code(200).send({ accessToken: token, expiresIn });
  });
}

import { createLocalJWKSet, createRemoteJWKSet, jwtVerify, type JWK, type JWTVerifyGetKey } from "jose";

export interface EntraIdentity {
  issuer: string;
  subject: string;
}

export type VerifyEntraIdTokenResult =
  | { ok: true; identity: EntraIdentity }
  | { ok: false; reason: "malformed" | "invalid" };

/**
 * Validates an Entra External ID (CIAM) ID token the website forwards to
 * POST /v2/web-session/token, per V2-ARCHITECTURE.md §5.2: "The web app
 * validates Entra tokens server-side using a maintained library and the
 * immutable (issuer, subject) identity key before calling
 * /v2/device/approve." This class is that independent, second validation —
 * the API never trusts the website's word alone that a token was valid;
 * it checks the signature itself against Entra's own JWKS.
 *
 * `expectedIssuer`/`expectedAudience` are the tenant's issuer URL and the
 * web app's registered Entra client ID — non-secret config, never accepted
 * from the request itself (Docs/contracts/inference-stream.md-style
 * discipline: never trust caller-supplied issuer metadata).
 */
export class EntraIdTokenVerifier {
  private constructor(
    private readonly getKey: JWTVerifyGetKey,
    private readonly expectedIssuer: string,
    private readonly expectedAudience: string
  ) {}

  /** Production: fetches Entra's real JWKS over the network. Cloud apply pending — no tenant exists yet to point this at. */
  static remote(jwksUri: string, expectedIssuer: string, expectedAudience: string): EntraIdTokenVerifier {
    return new EntraIdTokenVerifier(createRemoteJWKSet(new URL(jwksUri)), expectedIssuer, expectedAudience);
  }

  /** Test-only: verifies against an in-memory JWKS, no network. Never used outside tests. */
  static local(jwks: { keys: JWK[] }, expectedIssuer: string, expectedAudience: string): EntraIdTokenVerifier {
    return new EntraIdTokenVerifier(createLocalJWKSet(jwks), expectedIssuer, expectedAudience);
  }

  async verify(idToken: string): Promise<VerifyEntraIdTokenResult> {
    try {
      const { payload } = await jwtVerify(idToken, this.getKey, {
        issuer: this.expectedIssuer,
        audience: this.expectedAudience
      });
      if (typeof payload.sub !== "string" || typeof payload.iss !== "string") {
        return { ok: false, reason: "malformed" };
      }
      return { ok: true, identity: { issuer: payload.iss, subject: payload.sub } };
    } catch {
      return { ok: false, reason: "invalid" };
    }
  }
}

/**
 * WriterFlow-minted device access token claims (ADR-0012). This is never an
 * Entra token — the Mac app never holds one. Issuer is always
 * https://api.writerflow.app; validated against WriterFlow's own JWKS.
 */
export const WRITERFLOW_TOKEN_ISSUER = "https://api.writerflow.app";
export const WRITERFLOW_TOKEN_AUDIENCE = "https://api.writerflow.app";
export const WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const WRITERFLOW_REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

export interface WriterFlowAccessTokenClaims {
  iss: "https://api.writerflow.app";
  aud: "https://api.writerflow.app";
  sub: string; // user id (WriterFlow-internal, not the Entra `sub`)
  device_id: string;
  org_id: string;
  scope: string;
  iat: number;
  exp: number;
  jti: string;
}

export interface AuthenticatedRequestContext {
  userId: string;
  deviceId: string;
  organizationId: string;
  scopes: readonly string[];
}

/**
 * WriterFlow-minted web-session token (Stage 5.2 "second token issuer"
 * decision). Distinct `aud` from WriterFlowAccessTokenClaims — same
 * signing/JWKS infrastructure (ADR-0012's issuer), but a device token and a
 * web-session token can never be confused for one another at verification
 * time because the audience check alone rejects the wrong one.
 *
 * Minted by POST /v2/web-session/token after the website has independently
 * validated the user's Entra ID token server-side and forwarded it here.
 * Carries the raw (entra_issuer, entra_subject) pair, NOT a WriterFlow user
 * id — the account may not exist yet; POST /v2/device/approve is what
 * resolves/creates it, keyed on this immutable identity pair.
 */
export const WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE = "https://api.writerflow.app/web-session";
export const WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS = 5 * 60;

export interface WriterFlowWebSessionTokenClaims {
  iss: "https://api.writerflow.app";
  aud: "https://api.writerflow.app/web-session";
  entra_issuer: string;
  entra_subject: string;
  iat: number;
  exp: number;
  jti: string;
}

/**
 * WriterFlow-minted device access token claims (ADR-0012). This is never an
 * Entra token — the Mac app never holds one. Issuer is always
 * https://api.writerflow.app; validated against WriterFlow's own JWKS.
 */
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

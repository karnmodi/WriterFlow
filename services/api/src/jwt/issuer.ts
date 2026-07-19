import { SignJWT, decodeProtectedHeader, jwtVerify } from "jose";
import { randomUUID } from "node:crypto";
import {
  WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS,
  WRITERFLOW_TOKEN_AUDIENCE,
  WRITERFLOW_TOKEN_ISSUER,
  WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE,
  WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS,
  type WriterFlowAccessTokenClaims,
  type WriterFlowWebSessionTokenClaims
} from "@writerflow/shared";
import type { SigningKeyProvider } from "./keys.js";

async function sign(
  keys: SigningKeyProvider,
  audience: string,
  subject: string,
  claims: Record<string, string>,
  ttlSeconds: number
): Promise<string> {
  const { kid, privateKey } = await keys.getCurrentSigningKey();
  return new SignJWT(claims)
    .setProtectedHeader({ alg: "ES256", kid })
    .setIssuer(WRITERFLOW_TOKEN_ISSUER)
    .setAudience(audience)
    .setSubject(subject)
    .setJti(randomUUID())
    .setIssuedAt()
    .setExpirationTime(`${ttlSeconds}s`)
    .sign(privateKey);
}

type VerifyFailureReason = "malformed" | "unknown_kid" | "invalid";

async function verify(
  keys: SigningKeyProvider,
  audience: string,
  token: string
): Promise<{ ok: true; claims: unknown } | { ok: false; reason: VerifyFailureReason }> {
  let kid: string | undefined;
  try {
    ({ kid } = decodeProtectedHeader(token));
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (!kid) return { ok: false, reason: "malformed" };

  const verificationKey = await keys.getVerificationKey(kid);
  if (!verificationKey) return { ok: false, reason: "unknown_kid" };

  try {
    const { payload } = await jwtVerify(token, verificationKey, {
      issuer: WRITERFLOW_TOKEN_ISSUER,
      audience
    });
    return { ok: true, claims: payload };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}

export interface MintAccessTokenInput {
  userId: string;
  deviceId: string;
  organizationId: string;
  scope: string;
}

export async function mintAccessToken(
  keys: SigningKeyProvider,
  input: MintAccessTokenInput
): Promise<{ token: string; expiresIn: number }> {
  const token = await sign(
    keys,
    WRITERFLOW_TOKEN_AUDIENCE,
    input.userId,
    { device_id: input.deviceId, org_id: input.organizationId, scope: input.scope },
    WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS
  );
  return { token, expiresIn: WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS };
}

export type VerifyAccessTokenResult =
  | { ok: true; claims: WriterFlowAccessTokenClaims }
  | { ok: false; reason: VerifyFailureReason };

/**
 * Application-layer verification — defense in depth alongside APIM's own
 * validate-jwt (V2-ARCHITECTURE.md §5.2: "API Management's check is defense
 * in depth, not a replacement for application authorization").
 */
export async function verifyAccessToken(keys: SigningKeyProvider, token: string): Promise<VerifyAccessTokenResult> {
  const result = await verify(keys, WRITERFLOW_TOKEN_AUDIENCE, token);
  return result.ok ? { ok: true, claims: result.claims as WriterFlowAccessTokenClaims } : result;
}

export interface MintWebSessionTokenInput {
  entraIssuer: string;
  entraSubject: string;
}

/**
 * Stage 5.2 "second token issuer" decision: distinct audience from device
 * access tokens, minted only by POST /v2/web-session/token after the
 * website independently validates the caller's Entra ID token server-side.
 */
export async function mintWebSessionToken(
  keys: SigningKeyProvider,
  input: MintWebSessionTokenInput
): Promise<{ token: string; expiresIn: number }> {
  const token = await sign(
    keys,
    WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE,
    `${input.entraIssuer}|${input.entraSubject}`,
    { entra_issuer: input.entraIssuer, entra_subject: input.entraSubject },
    WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS
  );
  return { token, expiresIn: WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS };
}

export type VerifyWebSessionTokenResult =
  | { ok: true; claims: WriterFlowWebSessionTokenClaims }
  | { ok: false; reason: VerifyFailureReason };

export async function verifyWebSessionToken(
  keys: SigningKeyProvider,
  token: string
): Promise<VerifyWebSessionTokenResult> {
  const result = await verify(keys, WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE, token);
  return result.ok ? { ok: true, claims: result.claims as WriterFlowWebSessionTokenClaims } : result;
}

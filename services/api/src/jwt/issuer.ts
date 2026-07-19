import { SignJWT, decodeProtectedHeader, jwtVerify } from "jose";
import { randomUUID } from "node:crypto";
import {
  WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS,
  WRITERFLOW_TOKEN_AUDIENCE,
  WRITERFLOW_TOKEN_ISSUER,
  type WriterFlowAccessTokenClaims
} from "@writerflow/shared";
import type { SigningKeyProvider } from "./keys.js";

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
  const { kid, privateKey } = await keys.getCurrentSigningKey();
  const token = await new SignJWT({
    device_id: input.deviceId,
    org_id: input.organizationId,
    scope: input.scope
  })
    .setProtectedHeader({ alg: "ES256", kid })
    .setIssuer(WRITERFLOW_TOKEN_ISSUER)
    .setAudience(WRITERFLOW_TOKEN_AUDIENCE)
    .setSubject(input.userId)
    .setJti(randomUUID())
    .setIssuedAt()
    .setExpirationTime(`${WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS}s`)
    .sign(privateKey);
  return { token, expiresIn: WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS };
}

export type VerifyAccessTokenResult =
  | { ok: true; claims: WriterFlowAccessTokenClaims }
  | { ok: false; reason: "malformed" | "unknown_kid" | "invalid" };

/**
 * Application-layer verification — defense in depth alongside APIM's own
 * validate-jwt (V2-ARCHITECTURE.md §5.2: "API Management's check is defense
 * in depth, not a replacement for application authorization").
 */
export async function verifyAccessToken(
  keys: SigningKeyProvider,
  token: string
): Promise<VerifyAccessTokenResult> {
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
      audience: WRITERFLOW_TOKEN_AUDIENCE
    });
    return {
      ok: true,
      claims: payload as unknown as WriterFlowAccessTokenClaims
    };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}

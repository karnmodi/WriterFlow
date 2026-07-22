import { SignJWT, decodeProtectedHeader, jwtVerify } from "jose";
import { createHash, randomUUID } from "node:crypto";

function encodeBase64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? Buffer.from(value) : Buffer.from(value);
  return bytes.toString("base64url");
}
import {
  WRITERFLOW_ACCESS_TOKEN_TTL_SECONDS,
  WRITERFLOW_TOKEN_AUDIENCE,
  WRITERFLOW_TOKEN_ISSUER,
  WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE,
  WRITERFLOW_WEB_ACCOUNT_TOKEN_TTL_SECONDS,
  WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE,
  WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS,
  type WriterFlowAccessTokenClaims,
  type WriterFlowWebAccountTokenClaims,
  type WriterFlowWebSessionTokenClaims
} from "@writerflow/shared";
import type { EntraDisplayClaims } from "../entra/verifier.js";
import { displayFromStoredClaims } from "../entra/claims.js";
import type { SigningKeyProvider } from "./keys.js";

async function sign(
  keys: SigningKeyProvider,
  audience: string,
  subject: string,
  claims: Record<string, string>,
  ttlSeconds: number
): Promise<string> {
  const { kid, privateKey } = await keys.getCurrentSigningKey();
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    ...claims,
    iss: WRITERFLOW_TOKEN_ISSUER,
    aud: audience,
    sub: subject,
    jti: randomUUID(),
    iat: now,
    exp: now + ttlSeconds
  };

  if (keys.signDigest) {
    const protectedHeader = { alg: "ES256", typ: "JWT", kid };
    const encodedHeader = encodeBase64url(JSON.stringify(protectedHeader));
    const encodedPayload = encodeBase64url(JSON.stringify(payload));
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    const digest = createHash("sha256").update(signingInput).digest();
    const signature = await keys.signDigest(new Uint8Array(digest));
    return `${signingInput}.${encodeBase64url(signature)}`;
  }

  return new SignJWT(claims)
    .setProtectedHeader({ alg: "ES256", kid })
    .setIssuer(WRITERFLOW_TOKEN_ISSUER)
    .setAudience(audience)
    .setSubject(subject)
    .setJti(payload.jti)
    .setIssuedAt(now)
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
  displayClaims?: EntraDisplayClaims;
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
  const claims: Record<string, string> = {
    entra_issuer: input.entraIssuer,
    entra_subject: input.entraSubject
  };
  if (input.displayClaims && Object.keys(input.displayClaims).length > 0) {
    claims.entra_display_claims = JSON.stringify(input.displayClaims);
  }
  const token = await sign(
    keys,
    WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE,
    `${input.entraIssuer}|${input.entraSubject}`,
    claims,
    WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS
  );
  return { token, expiresIn: WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS };
}

/** Reconstructs the Entra identity (including display fields) from a verified web-session token. */
export function entraIdentityFromWebSessionClaims(claims: WriterFlowWebSessionTokenClaims): {
  issuer: string;
  subject: string;
  displayName: string | null;
  email: string | null;
  displayClaims: EntraDisplayClaims;
} {
  let displayClaims: EntraDisplayClaims = {};
  if (typeof claims.entra_display_claims === "string") {
    try {
      const parsed = JSON.parse(claims.entra_display_claims) as unknown;
      if (parsed != null && typeof parsed === "object" && !Array.isArray(parsed)) {
        displayClaims = parsed;
      }
    } catch {
      displayClaims = {};
    }
  }
  const displayName =
    displayClaims.name ??
    ([displayClaims.given_name, displayClaims.family_name].filter(Boolean).join(" ") || null);
  const email = displayClaims.email ?? null;
  const fromStored = displayFromStoredClaims(displayClaims);
  return {
    issuer: claims.entra_issuer,
    subject: claims.entra_subject,
    displayName: fromStored.displayName ?? displayName,
    email: fromStored.email ?? email,
    displayClaims
  };
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

export interface MintWebAccountTokenInput {
  userId: string;
  organizationId: string;
  entraIssuer: string;
  entraSubject: string;
  displayClaims?: EntraDisplayClaims;
}

/** ADR-0013: durable website account session (~1h). */
export async function mintWebAccountToken(
  keys: SigningKeyProvider,
  input: MintWebAccountTokenInput
): Promise<{ token: string; expiresIn: number }> {
  const claims: Record<string, string> = {
    org_id: input.organizationId,
    entra_issuer: input.entraIssuer,
    entra_subject: input.entraSubject
  };
  if (input.displayClaims && Object.keys(input.displayClaims).length > 0) {
    claims.entra_display_claims = JSON.stringify(input.displayClaims);
  }
  const token = await sign(
    keys,
    WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE,
    input.userId,
    claims,
    WRITERFLOW_WEB_ACCOUNT_TOKEN_TTL_SECONDS
  );
  return { token, expiresIn: WRITERFLOW_WEB_ACCOUNT_TOKEN_TTL_SECONDS };
}

export type VerifyWebAccountTokenResult =
  | { ok: true; claims: WriterFlowWebAccountTokenClaims }
  | { ok: false; reason: VerifyFailureReason };

export async function verifyWebAccountToken(
  keys: SigningKeyProvider,
  token: string
): Promise<VerifyWebAccountTokenResult> {
  const result = await verify(keys, WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE, token);
  return result.ok ? { ok: true, claims: result.claims as WriterFlowWebAccountTokenClaims } : result;
}

/** Mint a short web-session bridge from a verified web-account token (pairing reuse). */
export async function mintWebSessionBridgeFromAccount(
  keys: SigningKeyProvider,
  claims: WriterFlowWebAccountTokenClaims
): Promise<{ token: string; expiresIn: number }> {
  let displayClaims: EntraDisplayClaims = {};
  if (typeof claims.entra_display_claims === "string") {
    try {
      const parsed = JSON.parse(claims.entra_display_claims) as unknown;
      if (parsed != null && typeof parsed === "object" && !Array.isArray(parsed)) {
        displayClaims = parsed as EntraDisplayClaims;
      }
    } catch {
      displayClaims = {};
    }
  }
  return mintWebSessionToken(keys, {
    entraIssuer: claims.entra_issuer,
    entraSubject: claims.entra_subject,
    displayClaims
  });
}

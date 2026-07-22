import type { JWTPayload } from "jose";
import type { EntraDisplayClaims, EntraIdentity } from "./verifier.js";

function looksLikeEmail(value: string): boolean {
  return value.includes("@");
}

/** CIAM email-OTP users often get a literal "unknown" name claim when Given Name/Surname aren't mapped. */
const PLACEHOLDER_DISPLAY_NAMES = new Set(["unknown", "unknown user", "n/a", "na", "none"]);

export function isPlaceholderDisplayName(value: string | null | undefined): boolean {
  if (value == null) return false;
  const normalized = value.trim().toLowerCase();
  return normalized.length === 0 || PLACEHOLDER_DISPLAY_NAMES.has(normalized);
}

function claimString(source: Record<string, unknown>, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed) return trimmed;
    }
  }
  return null;
}

/**
 * Reads Entra External ID user-flow attributes from a JWT or userinfo payload.
 * CIAM programmable names (givenName, surname) differ from OIDC defaults
 * (given_name, family_name) — both are accepted.
 */
export function extractDisplayFromPayload(payload: JWTPayload | Record<string, unknown>): Pick<
  EntraIdentity,
  "displayName" | "email" | "displayClaims"
> {
  const record = payload as Record<string, unknown>;
  const givenName = claimString(record, "given_name", "givenName");
  const familyName = claimString(record, "family_name", "family_name", "surname");
  const rawFullName = claimString(record, "name", "displayName");
  const fullName = rawFullName != null && !isPlaceholderDisplayName(rawFullName) ? rawFullName : null;

  const email =
    claimString(record, "email") ??
    (Array.isArray(record.emails) && typeof record.emails[0] === "string" ? record.emails[0].trim() : null) ??
    (typeof record.preferred_username === "string" && looksLikeEmail(record.preferred_username)
      ? record.preferred_username.trim()
      : null);

  const displayClaims: EntraDisplayClaims = {};
  if (fullName) displayClaims.name = fullName;
  if (givenName) displayClaims.given_name = givenName;
  if (familyName) displayClaims.family_name = familyName;
  if (email) displayClaims.email = email;

  const displayName = fullName ?? ([givenName, familyName].filter(Boolean).join(" ") || null);

  return { displayName, email, displayClaims };
}

/** Maps auth_identities.display_claims jsonb back to AccountSnapshot fields. */
export function displayFromStoredClaims(claims: unknown): Pick<EntraIdentity, "displayName" | "email"> {
  if (claims == null || typeof claims !== "object" || Array.isArray(claims)) {
    return { displayName: null, email: null };
  }
  return extractDisplayFromPayload(claims as Record<string, unknown>);
}

/** Fills missing display fields on an identity from a second payload (e.g. userinfo). */
export function mergeIdentityDisplay(
  identity: EntraIdentity,
  supplemental: Pick<EntraIdentity, "displayName" | "email" | "displayClaims">
): EntraIdentity {
  const displayClaims: EntraDisplayClaims = { ...supplemental.displayClaims, ...identity.displayClaims };
  for (const [key, value] of Object.entries(supplemental.displayClaims) as [keyof EntraDisplayClaims, string | undefined][]) {
    if (value && !displayClaims[key]) displayClaims[key] = value;
  }

  const merged = extractDisplayFromPayload(displayClaims as Record<string, unknown>);
  const pickDisplayName = (...candidates: (string | null | undefined)[]): string | null => {
    for (const candidate of candidates) {
      if (candidate && !isPlaceholderDisplayName(candidate)) return candidate;
    }
    return null;
  };
  return {
    ...identity,
    displayName: pickDisplayName(supplemental.displayName, identity.displayName, merged.displayName),
    email: identity.email ?? supplemental.email ?? merged.email,
    displayClaims
  };
}

export function resolveUserInfoUrl(issuer: string, configured?: string): string {
  if (configured) return configured;
  if (issuer.includes("ciamlogin.com")) {
    return "https://graph.microsoft.com/oidc/userinfo";
  }
  if (issuer.endsWith("/v2.0")) {
    return issuer.replace(/\/v2\.0$/, "/openid/v2.0/userinfo");
  }
  return `${issuer.replace(/\/$/, "")}/userinfo`;
}

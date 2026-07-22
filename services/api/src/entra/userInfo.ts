import { extractDisplayFromPayload, isPlaceholderDisplayName, mergeIdentityDisplay } from "./claims.js";
import { resolveEntraUserInfoEndpoint } from "./discovery.js";
import type { EntraIdentity } from "./verifier.js";

/** Fetches Entra userinfo when the ID token omits user-flow attributes (common in CIAM). */
export async function enrichIdentityFromUserInfo(
  identity: EntraIdentity,
  accessToken: string,
  issuer: string,
  configuredUserInfoUrl?: string
): Promise<EntraIdentity> {
  if (identity.displayName && !isPlaceholderDisplayName(identity.displayName)) return identity;

  const userInfoUrl = await resolveEntraUserInfoEndpoint(issuer, configuredUserInfoUrl);
  let response: Response;
  try {
    response = await fetch(userInfoUrl, {
      headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" }
    });
  } catch {
    return identity;
  }
  if (!response.ok) return identity;

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    return identity;
  }
  if (payload == null || typeof payload !== "object" || Array.isArray(payload)) {
    return identity;
  }

  const supplemental = extractDisplayFromPayload(payload as Record<string, unknown>);
  return mergeIdentityDisplay(identity, supplemental);
}

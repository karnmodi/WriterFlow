/** Pull a compact Entra logout_hint (email/UPN) from ID-token claims. */
export function logoutHintFromClaims(claims: Record<string, unknown> | undefined | null): string | null {
  if (!claims) return null;
  for (const key of ["email", "preferred_username", "upn", "unique_name"] as const) {
    const value = claims[key];
    if (typeof value === "string" && value.includes("@")) {
      return value.trim();
    }
  }
  if (Array.isArray(claims.emails) && typeof claims.emails[0] === "string" && claims.emails[0].includes("@")) {
    return claims.emails[0].trim();
  }
  return null;
}

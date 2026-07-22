/** CIAM discovery documents point userinfo at Graph, not {tenant}/openid/v2.0/userinfo. */
const CIAM_GRAPH_USERINFO = "https://graph.microsoft.com/oidc/userinfo";

const cachedUserInfoByIssuer = new Map<string, string>();

/**
 * Resolves Entra's userinfo endpoint from OIDC discovery (cached per issuer).
 * Falls back to Graph for *.ciamlogin.com tenants when discovery is unreachable.
 */
export async function resolveEntraUserInfoEndpoint(issuer: string, configured?: string): Promise<string> {
  if (configured) return configured;

  const cached = cachedUserInfoByIssuer.get(issuer);
  if (cached) return cached;

  try {
    const discoveryUrl = new URL(".well-known/openid-configuration", issuer.endsWith("/") ? issuer : `${issuer}/`);
    const response = await fetch(discoveryUrl, { headers: { Accept: "application/json" } });
    if (response.ok) {
      const document = (await response.json()) as { userinfo_endpoint?: string };
      if (typeof document.userinfo_endpoint === "string" && document.userinfo_endpoint.length > 0) {
        cachedUserInfoByIssuer.set(issuer, document.userinfo_endpoint);
        return document.userinfo_endpoint;
      }
    }
  } catch {
    // Discovery fetch failed — use CIAM fallback below.
  }

  const fallback = issuer.includes("ciamlogin.com") ? CIAM_GRAPH_USERINFO : `${issuer.replace(/\/$/, "")}/userinfo`;
  cachedUserInfoByIssuer.set(issuer, fallback);
  return fallback;
}

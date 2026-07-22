import * as client from "openid-client";

/**
 * Server-only Entra External ID (CIAM) OIDC client — V2-ARCHITECTURE.md §5.1
 * step 3: "the web app runs Entra sign-in... provisions... and calls POST
 * /v2/device/approve under its authenticated session." This module is that
 * confidential/public client; it never runs in the browser (no "use client",
 * imported only from Route Handlers).
 *
 * Uses openid-client's discovery() rather than hand-fetching the metadata
 * document — it fetches issuer/jwks_uri/token_endpoint itself and verifies
 * the ID token's signature against the real JWKS, so this module doesn't
 * duplicate that verification logic (services/api's EntraIdTokenVerifier
 * does its own independent check regardless, per that module's own "never
 * trust the caller's say-so" comment).
 */

let configPromise: Promise<client.Configuration> | null = null;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var ${name} — see website/README.md's Entra sign-in section.`);
  }
  return value;
}

/** Cached across requests within one server process — discovery() does a real network fetch. */
export function getEntraConfig(): Promise<client.Configuration> {
  if (!configPromise) {
    const issuer = new URL(requireEnv("ENTRA_TENANT_ISSUER"));
    const clientId = requireEnv("ENTRA_WEB_CLIENT_ID");
    // Optional — try without a secret first (PKCE-only public client). Set
    // ENTRA_WEB_CLIENT_SECRET if the token endpoint rejects unauthenticated
    // requests for this client (invalid_client).
    const clientSecret = process.env["ENTRA_WEB_CLIENT_SECRET"];
    configPromise = client.discovery(issuer, clientId, clientSecret);
  }
  return configPromise;
}

export function pairRedirectUri(): string {
  return requireEnv("PAIR_REDIRECT_URI");
}

export function authRedirectUri(): string {
  return process.env["AUTH_REDIRECT_URI"] ?? pairRedirectUri().replace("/pair/callback", "/auth/callback");
}

export function accountLogoutRedirectUri(): string {
  const siteOrigin = process.env["NEXT_PUBLIC_SITE_ORIGIN"];
  if (siteOrigin) return `${siteOrigin.replace(/\/$/, "")}/account?signedOut=1`;
  return authRedirectUri().replace("/auth/callback", "/account?signedOut=1");
}

export interface EntraLogoutParams {
  idTokenHint?: string;
  logoutHint?: string;
}

/**
 * Build Entra OIDC logout URL (end_session_endpoint).
 * Always includes client_id (required by Entra External ID / CIAM).
 * Prefer id_token_hint and/or logout_hint (email) so CIAM does not show an
 * empty "Pick an account" screen.
 */
export async function buildEntraLogoutUrl(params: EntraLogoutParams = {}): Promise<string> {
  const config = await getEntraConfig();
  const metadata = config.serverMetadata();
  const endSession = metadata.end_session_endpoint;
  if (!endSession) {
    throw new Error("Entra discovery document has no end_session_endpoint — register a logout redirect URI.");
  }
  const url = new URL(endSession);
  url.searchParams.set("client_id", requireEnv("ENTRA_WEB_CLIENT_ID"));
  url.searchParams.set("post_logout_redirect_uri", accountLogoutRedirectUri());
  if (params.idTokenHint) {
    url.searchParams.set("id_token_hint", params.idTokenHint);
  }
  if (params.logoutHint) {
    url.searchParams.set("logout_hint", params.logoutHint);
  }
  return url.toString();
}

/** True when we have enough to avoid CIAM's empty account-picker dead end. */
export function canFederatedLogout(params: EntraLogoutParams): boolean {
  return Boolean(params.idTokenHint || params.logoutHint);
}

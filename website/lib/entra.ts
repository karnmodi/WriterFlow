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

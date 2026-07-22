/**
 * Route-handler tests for /pair/start and /auth/start.
 * Validates validation and redirect/cookie behavior using mocked Entra config.
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";

process.env.ENTRA_TENANT_ISSUER ??= "https://login.example.com/tenant/v2.0";
process.env.ENTRA_WEB_CLIENT_ID ??= "test-client-id";
process.env.PAIR_REDIRECT_URI ??= "http://localhost:3000/pair/callback";
process.env.AUTH_REDIRECT_URI ??= "http://localhost:3000/auth/callback";

// Stub openid-client before route modules load.
const { mock } = await import("node:test");
mock.module("openid-client", {
  namedExports: {
    discovery: async () => ({
      serverMetadata: () => ({
        authorization_endpoint: "https://login.example.com/authorize"
      })
    }),
    buildAuthorizationUrl: (_config, params) => {
      const url = new URL("https://login.example.com/authorize");
      for (const [key, value] of Object.entries(params)) {
        if (value != null) url.searchParams.set(key, String(value));
      }
      return url;
    },
    randomPKCECodeVerifier: () => "test-verifier-012345678901234567890123456789012345678901234567890",
    calculatePKCECodeChallenge: async () => "test-challenge"
  }
});

describe("GET /pair/start", () => {
  it("returns 400 when user_code is missing", async () => {
    const { GET } = await import("../app/pair/start/route.ts");
    const response = await GET({ nextUrl: new URL("http://localhost:3000/pair/start") } as never);
    assert.equal(response.status, 400);
  });
});

describe("GET /auth/start", () => {
  it("redirects with auth PKCE cookie", async () => {
    const { GET } = await import("../app/auth/start/route.ts");
    const response = await GET({ nextUrl: new URL("http://localhost:3000/auth/start") } as never);
    assert.equal(response.status, 307);
    const cookie = response.cookies.get("wf_auth_pkce");
    assert.ok(cookie?.value.includes("/account"));
  });
});

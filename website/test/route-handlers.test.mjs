/**
 * Route-handler tests for /pair/start and /auth/start.
 * Validates validation and redirect/cookie behavior using mocked Entra config.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
    calculatePKCECodeChallenge: async () => "test-challenge",
    authorizationCodeGrant: async () => ({
      id_token: "entra-id-token",
      access_token: "entra-access-token",
      claims: () => ({ login_hint: "test@example.com" })
    })
  }
});

describe("membership plan scaffold", () => {
  it("keeps Free concrete and Pro honestly unpriced", async () => {
    const { membershipPlans } = await import("../lib/membership-plans.ts");
    const free = membershipPlans.find((plan) => plan.id === "free");
    const pro = membershipPlans.find((plan) => plan.id === "pro");

    assert.equal(free?.unitAllowance, 500);
    assert.equal(free?.priceCents, 0);
    assert.equal(free?.availability, "available");
    assert.equal(pro?.unitAllowance, null);
    assert.equal(pro?.priceCents, null);
    assert.equal(pro?.availability, "in-development");
    assert.ok(pro?.featureFlags.includes("premium_route"));
  });
});

describe("rewrite demonstration timing", () => {
  it("always leaves a reading pause after the full draft can be typed", async () => {
    const { rewriteDemoTypingDuration } = await import("../lib/rewrite-demo.ts");
    const messageLength = 320;
    const typingOnly = Math.ceil(messageLength / 2) * 42;

    assert.equal(rewriteDemoTypingDuration(messageLength, 2), typingOnly + 1200);
  });
});

describe("v2 website visual contracts", () => {
  it("keeps text selection readable and the inverse footer mark distinct", () => {
    const styles = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");
    const brandMark = readFileSync(new URL("../components/BrandMark.tsx", import.meta.url), "utf8");

    assert.match(styles, /::selection\s*\{[^}]*color:\s*white;/s);
    assert.match(styles, /footer \[aria-label="WriterFlow home"\] svg/);
    assert.ok(brandMark.includes('stroke={inverse ? "#11131a" : "#f4f1e9"}'));
  });

  it("documents semantic colour placement and accessibility guidance", () => {
    const guide = readFileSync(new URL("../UI-V2.md", import.meta.url), "utf8");

    for (const variant of ["Paper", "Soft / lavender", "Prism", "Ink", "Amber", "Success"]) {
      assert.ok(guide.includes(variant));
    }
    assert.ok(guide.includes("WCAG AA"));
    assert.ok(guide.includes("Colour is never the sole indicator"));
  });
});

describe("GET /pair/start", () => {
  it("returns 400 when user_code is missing", async () => {
    const { GET } = await import("../app/pair/start/route.ts");
    const response = await GET({ nextUrl: new URL("http://localhost:3000/pair/start") });
    assert.equal(response.status, 400);
  });
});

describe("GET /auth/start", () => {
  it("redirects with auth PKCE cookie", async () => {
    const { GET } = await import("../app/auth/start/route.ts");
    const response = await GET({ nextUrl: new URL("http://localhost:3000/auth/start") });
    assert.equal(response.status, 307);
    const cookie = response.cookies.get("wf_auth_pkce");
    assert.ok(cookie?.value.includes("/account"));
  });
});

describe("WriterFlow API errors", () => {
  it("returns support-safe sign-in copy with the request reference", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => Response.json(
      {
        code: "AUTH_INVALID",
        message: "provider detail that must not reach the browser",
        requestId: "req-support-123"
      },
      { status: 403 }
    );

    try {
      const { mintWebAccountToken } = await import("../lib/writerflow-api.ts");
      await assert.rejects(
        mintWebAccountToken({ idToken: "entra-id-token" }),
        (error) => {
          assert.equal(
            error.message,
            "This account cannot access WriterFlow. Reference: req-support-123."
          );
          assert.equal(error.message.includes("provider detail"), false);
          return true;
        }
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("GET /pair/callback", () => {
  it("exchanges Entra tokens, approves the device, and redirects successfully", async () => {
    const originalFetch = globalThis.fetch;
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      if (String(url).endsWith("/web-session/token")) {
        return Response.json({ accessToken: "writerflow-web-session" });
      }
      if (String(url).endsWith("/device/approve")) {
        return new Response(null, { status: 204 });
      }
      if (String(url).endsWith("/web-account/token")) {
        return Response.json({ accessToken: "writerflow-account", expiresIn: 300 });
      }
      throw new Error(`unexpected fetch ${url}`);
    };

    try {
      const { GET } = await import("../app/pair/callback/route.ts");
      const request = {
        url: "http://localhost:3000/pair/callback?code=entra-code",
        headers: new Headers({ host: "localhost:3000", "x-forwarded-proto": "http" }),
        cookies: {
          get: (name) => name === "wf_pair_pkce"
            ? { value: JSON.stringify({ userCode: "ABCD-EFGH", codeVerifier: "test-verifier" }) }
            : undefined
        }
      };

      const response = await GET(request);

      assert.equal(response.status, 307);
      assert.equal(response.headers.get("location"), "http://localhost:3000/pair?status=success");
      assert.equal(calls.length, 3);
      assert.ok(calls[1].url.endsWith("/device/approve"));
      assert.equal(
        JSON.parse(String(calls[1].init?.body)).userCode,
        "ABCD-EFGH"
      );
      assert.ok(response.cookies.get("wf_web_account"));
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("GET /auth/callback", () => {
  it("exchanges Entra tokens and establishes the web-account session", async () => {
    const originalFetch = globalThis.fetch;
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      if (String(url).endsWith("/web-account/token")) {
        return Response.json({ accessToken: "writerflow-account", expiresIn: 3600 });
      }
      throw new Error(`unexpected fetch ${url}`);
    };

    try {
      const { GET } = await import("../app/auth/callback/route.ts");
      const request = {
        url: "http://localhost:3000/auth/callback?code=entra-code",
        headers: new Headers({ host: "localhost:3000", "x-forwarded-proto": "http" }),
        cookies: {
          get: (name) => name === "wf_auth_pkce"
            ? { value: JSON.stringify({ returnTo: "/account", codeVerifier: "test-verifier" }) }
            : undefined
        }
      };

      const response = await GET(request);

      assert.equal(response.status, 307);
      assert.equal(response.headers.get("location"), "http://localhost:3000/account");
      assert.equal(calls.length, 1);
      assert.ok(calls[0].url.endsWith("/web-account/token"));
      const payload = JSON.parse(String(calls[0].init?.body));
      assert.equal(payload.idToken, "entra-id-token");
      assert.equal(payload.accessToken, "entra-access-token");
      assert.equal(response.cookies.get("wf_web_account")?.value, "writerflow-account");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("GET /auth/sign-out", () => {
  it("clears local auth cookies and returns to a signed-out account page", async () => {
    const { GET } = await import("../app/auth/sign-out/route.ts");
    const request = {
      headers: new Headers({ host: "localhost:3000", "x-forwarded-proto": "http" }),
      cookies: { get: () => undefined }
    };

    const response = await GET(request);

    assert.equal(response.status, 307);
    assert.equal(
      response.headers.get("location"),
      "http://localhost:3000/account?signedOut=1"
    );
    const setCookies = response.headers.getSetCookie().join("\n");
    assert.ok(setCookies.includes("wf_web_account="));
    assert.ok(setCookies.includes("wf_auth_pkce="));
  });
});

describe("private-beta product copy", () => {
  it("documents cloud processing, pairing, local encryption, and billing status without stale BYO claims", () => {
    const pages = [
      "../app/page.tsx",
      "../app/install/page.tsx",
      "../app/membership/page.tsx",
      "../app/privacy/page.tsx",
      "../app/account/page.tsx"
    ].map((path) => readFileSync(new URL(path, import.meta.url), "utf8")).join("\n");

    assert.ok(pages.includes("private beta"));
    assert.ok(pages.includes("device pairing"));
    assert.ok(pages.includes("SQLCipher"));
    assert.ok(pages.includes("Billing unavailable"));
    assert.equal(/bring-your-own|Your Azure OpenAI|No WriterFlow account/i.test(pages), false);
  });

  it("retains keyboard, mobile, and reduced-motion accessibility support", () => {
    const layout = readFileSync(new URL("../app/layout.tsx", import.meta.url), "utf8");
    const styles = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");
    const home = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");

    assert.ok(layout.includes("skip-link"));
    assert.ok(styles.includes("prefers-reduced-motion"));
    assert.ok(home.includes("sm:"));
    assert.ok(home.includes("md:"));
  });
});

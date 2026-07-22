import { describe, expect, it } from "vitest";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { EntraIdTokenVerifier, extractDisplayFromPayload } from "../src/entra/verifier.js";

const ISSUER = "https://writerflow.ciamlogin.com/tenant-id/v2.0";
const AUDIENCE = "web-app-client-id";

async function makeTestIdp() {
  const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
  const publicJwk = await exportJWK(publicKey);
  publicJwk.kid = "test-kid";
  publicJwk.alg = "ES256";
  return {
    jwks: { keys: [publicJwk] },
    async mintIdToken(
      overrides: {
        issuer?: string;
        audience?: string;
        subject?: string;
        expired?: boolean;
        claims?: Record<string, unknown>;
      } = {}
    ) {
      return new SignJWT(overrides.claims ?? {})
        .setProtectedHeader({ alg: "ES256", kid: "test-kid" })
        .setIssuer(overrides.issuer ?? ISSUER)
        .setAudience(overrides.audience ?? AUDIENCE)
        .setSubject(overrides.subject ?? "entra-user-1")
        .setIssuedAt()
        .setExpirationTime(overrides.expired ? Math.floor(Date.now() / 1000) - 1 : "10m")
        .sign(privateKey);
    }
  };
}

describe("EntraIdTokenVerifier", () => {
  it("accepts a validly-signed ID token and extracts (issuer, subject)", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await idp.mintIdToken();
    const result = await verifier.verify(token);
    expect(result).toEqual({
      ok: true,
      identity: {
        issuer: ISSUER,
        subject: "entra-user-1",
        displayName: null,
        email: null,
        displayClaims: {}
      }
    });
  });

  it("extracts display name and email from profile claims", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await idp.mintIdToken({
      claims: {
        name: "Karan Singh",
        email: "karan@example.com",
        given_name: "Karan",
        family_name: "Singh"
      }
    });
    const result = await verifier.verify(token);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.identity.displayName).toBe("Karan Singh");
      expect(result.identity.email).toBe("karan@example.com");
      expect(result.identity.displayClaims).toEqual({
        name: "Karan Singh",
        email: "karan@example.com",
        given_name: "Karan",
        family_name: "Singh"
      });
    }
  });

  it("extracts CIAM user-flow attributes givenName and surname", () => {
    const display = extractDisplayFromPayload({
      givenName: "Karan",
      surname: "Singh",
      email: "karan@example.com"
    });
    expect(display.displayName).toBe("Karan Singh");
    expect(display.email).toBe("karan@example.com");
    expect(display.displayClaims).toEqual({
      given_name: "Karan",
      family_name: "Singh",
      email: "karan@example.com"
    });
  });

  it("builds display name from given_name and family_name when name is absent", () => {
    const display = extractDisplayFromPayload({
      given_name: "Karan",
      family_name: "Singh",
      preferred_username: "karan@example.com"
    });
    expect(display.displayName).toBe("Karan Singh");
    expect(display.email).toBe("karan@example.com");
  });

  it("ignores CIAM placeholder name unknown and falls back to given_name + family_name", () => {
    const display = extractDisplayFromPayload({
      name: "unknown",
      given_name: "Karan",
      family_name: "Modi",
      email: "karan@example.com"
    });
    expect(display.displayName).toBe("Karan Modi");
    expect(display.displayClaims.name).toBeUndefined();
    expect(display.displayClaims.given_name).toBe("Karan");
  });

  it("returns null displayName when only placeholder name and email are present", () => {
    const display = extractDisplayFromPayload({
      name: "unknown",
      email: "karanmodi3282@gmail.com"
    });
    expect(display.displayName).toBeNull();
    expect(display.email).toBe("karanmodi3282@gmail.com");
    expect(display.displayClaims.name).toBeUndefined();
  });

  it("rejects a token from a different signing key (not this IdP)", async () => {
    const idp = await makeTestIdp();
    const otherIdp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await otherIdp.mintIdToken();
    const result = await verifier.verify(token);
    expect(result).toEqual({ ok: false, reason: "invalid" });
  });

  it("rejects the wrong issuer", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await idp.mintIdToken({ issuer: "https://evil.example/tenant/v2.0" });
    const result = await verifier.verify(token);
    expect(result).toEqual({ ok: false, reason: "invalid" });
  });

  it("rejects the wrong audience", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await idp.mintIdToken({ audience: "some-other-client-id" });
    const result = await verifier.verify(token);
    expect(result).toEqual({ ok: false, reason: "invalid" });
  });

  it("rejects an expired token", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const token = await idp.mintIdToken({ expired: true });
    const result = await verifier.verify(token);
    expect(result).toEqual({ ok: false, reason: "invalid" });
  });

  it("rejects a malformed token", async () => {
    const idp = await makeTestIdp();
    const verifier = EntraIdTokenVerifier.local(idp.jwks, ISSUER, AUDIENCE);
    const result = await verifier.verify("not-a-jwt");
    expect(result).toEqual({ ok: false, reason: "invalid" });
  });
});

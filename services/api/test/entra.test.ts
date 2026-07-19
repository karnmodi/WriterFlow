import { describe, expect, it } from "vitest";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { EntraIdTokenVerifier } from "../src/entra/verifier.js";

const ISSUER = "https://writerflow.ciamlogin.com/tenant-id/v2.0";
const AUDIENCE = "web-app-client-id";

async function makeTestIdp() {
  const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
  const publicJwk = await exportJWK(publicKey);
  publicJwk.kid = "test-kid";
  publicJwk.alg = "ES256";
  return {
    jwks: { keys: [publicJwk] },
    async mintIdToken(overrides: { issuer?: string; audience?: string; subject?: string; expired?: boolean } = {}) {
      return new SignJWT({})
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
    expect(result).toEqual({ ok: true, identity: { issuer: ISSUER, subject: "entra-user-1" } });
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

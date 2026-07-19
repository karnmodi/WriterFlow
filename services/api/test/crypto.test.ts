import { describe, expect, it } from "vitest";
import { createHash, randomBytes } from "node:crypto";
import { computeS256Challenge, verifyPkce } from "../src/crypto/pkce.js";
import { generateOpaqueToken, generateUserCode, hashToken } from "../src/crypto/tokens.js";

describe("PKCE S256", () => {
  it("verifies a matching verifier/challenge pair", () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    expect(verifyPkce(verifier, challenge)).toBe(true);
  });

  it("rejects a wrong verifier", () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const wrongVerifier = randomBytes(32).toString("base64url");
    expect(verifyPkce(wrongVerifier, challenge)).toBe(false);
  });

  it("computes the exact RFC 7636 S256 transform", () => {
    const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const expected = createHash("sha256").update(verifier).digest("base64url");
    expect(computeS256Challenge(verifier)).toBe(expected);
  });
});

describe("opaque token / user code generation", () => {
  it("generates high-entropy, unique device/refresh tokens", () => {
    const tokens = new Set(Array.from({ length: 1000 }, () => generateOpaqueToken()));
    expect(tokens.size).toBe(1000);
    for (const t of tokens) expect(t.length).toBeGreaterThan(30);
  });

  it("user codes match the AAAA-AAAA shape and avoid ambiguous characters", () => {
    for (let i = 0; i < 200; i++) {
      const code = generateUserCode();
      expect(code).toMatch(/^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTVWXYZ23456789]{4}$/);
      expect(code).not.toMatch(/[01ILOU]/);
    }
  });

  it("hashToken is deterministic and matches sha256 hex", () => {
    const token = "example-token";
    const expected = createHash("sha256").update(token).digest("hex");
    expect(hashToken(token)).toBe(expected);
    expect(hashToken(token)).toBe(hashToken(token));
  });
});

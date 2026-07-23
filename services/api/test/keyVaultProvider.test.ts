import { describe, expect, it } from "vitest";
import { jwkFromAzureKeyVault, parsePreviousKeyNames } from "../src/jwt/keyVaultProvider.js";

describe("jwkFromAzureKeyVault", () => {
  it("maps an Azure EC P-256 public key to a jose-compatible JWK", () => {
    const jwk = jwkFromAzureKeyVault({
      kty: "EC",
      crv: "P-256",
      x: Buffer.from("test-x"),
      y: Buffer.from("test-y")
    });
    expect(jwk).toEqual({
      kty: "EC",
      crv: "P-256",
      x: Buffer.from("test-x").toString("base64url"),
      y: Buffer.from("test-y").toString("base64url")
    });
  });

  it("rejects non-EC keys", () => {
    expect(() => jwkFromAzureKeyVault({ kty: "RSA" })).toThrow(/Unsupported Key Vault key type/);
  });
});

describe("parsePreviousKeyNames", () => {
  it("keeps unique retired keys and excludes the active key", () => {
    expect(parsePreviousKeyNames("jwt-2026-06, jwt-current, jwt-2026-06, jwt-2026-05", "jwt-current"))
      .toEqual(["jwt-2026-06", "jwt-2026-05"]);
  });
});

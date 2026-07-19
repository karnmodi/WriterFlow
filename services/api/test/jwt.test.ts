import { describe, expect, it } from "vitest";
import { SignJWT } from "jose";
import { LocalDevSigningKeyProvider } from "../src/jwt/keys.js";
import {
  mintAccessToken,
  mintWebSessionToken,
  verifyAccessToken,
  verifyWebSessionToken
} from "../src/jwt/issuer.js";

describe("device-token issuer", () => {
  it("mints a token that verifies with the correct claims", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { token, expiresIn } = await mintAccessToken(keys, {
      userId: "user-1",
      deviceId: "device-1",
      organizationId: "org-1",
      scope: "device"
    });
    expect(expiresIn).toBe(900);

    const result = await verifyAccessToken(keys, token);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.claims.sub).toBe("user-1");
      expect(result.claims.device_id).toBe("device-1");
      expect(result.claims.org_id).toBe("org-1");
      expect(result.claims.iss).toBe("https://api.writerflow.app");
      expect(result.claims.aud).toBe("https://api.writerflow.app");
    }
  });

  it("rejects a token signed by a different (unknown-kid) key", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const otherKeys = new LocalDevSigningKeyProvider();
    const { token } = await mintAccessToken(otherKeys, {
      userId: "user-1",
      deviceId: "device-1",
      organizationId: "org-1",
      scope: "device"
    });
    const result = await verifyAccessToken(keys, token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("unknown_kid");
  });

  it("rejects a malformed token", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const result = await verifyAccessToken(keys, "not-a-jwt");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("malformed");
  });

  it("rejects a token with the wrong issuer", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { kid, privateKey } = await keys.getCurrentSigningKey();
    const token = await new SignJWT({ device_id: "d", org_id: "o", scope: "device" })
      .setProtectedHeader({ alg: "ES256", kid })
      .setIssuer("https://evil.example")
      .setAudience("https://api.writerflow.app")
      .setSubject("user-1")
      .setIssuedAt()
      .setExpirationTime("15m")
      .sign(privateKey);
    const result = await verifyAccessToken(keys, token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("invalid");
  });

  it("rejects a token with the wrong audience", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { kid, privateKey } = await keys.getCurrentSigningKey();
    const token = await new SignJWT({ device_id: "d", org_id: "o", scope: "device" })
      .setProtectedHeader({ alg: "ES256", kid })
      .setIssuer("https://api.writerflow.app")
      .setAudience("https://evil.example")
      .setSubject("user-1")
      .setIssuedAt()
      .setExpirationTime("15m")
      .sign(privateKey);
    const result = await verifyAccessToken(keys, token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("invalid");
  });

  it("rejects an expired token", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { kid, privateKey } = await keys.getCurrentSigningKey();
    const token = await new SignJWT({ device_id: "d", org_id: "o", scope: "device" })
      .setProtectedHeader({ alg: "ES256", kid })
      .setIssuer("https://api.writerflow.app")
      .setAudience("https://api.writerflow.app")
      .setSubject("user-1")
      .setIssuedAt(Math.floor(Date.now() / 1000) - 3600)
      .setExpirationTime(Math.floor(Date.now() / 1000) - 1)
      .sign(privateKey);
    const result = await verifyAccessToken(keys, token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("invalid");
  });

  it("publishes a JWKS with the current public key and no private material", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const jwks = await keys.getPublicJwks();
    expect(jwks.keys).toHaveLength(1);
    const key = jwks.keys[0];
    expect(key).toBeDefined();
    expect(key?.kty).toBe("EC");
    expect(key?.d).toBeUndefined();
    expect(key?.kid).toBeDefined();
    expect(key?.alg).toBe("ES256");
    expect(key?.use).toBe("sig");
  });
});

describe("web-session token (Stage 5.2 second-issuer decision)", () => {
  it("mints a token that verifies with the entra identity claims", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { token, expiresIn } = await mintWebSessionToken(keys, {
      entraIssuer: "https://writerflow.ciamlogin.com/tenant-id/v2.0",
      entraSubject: "entra-user-1"
    });
    expect(expiresIn).toBe(300);
    const result = await verifyWebSessionToken(keys, token);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.claims.entra_issuer).toBe("https://writerflow.ciamlogin.com/tenant-id/v2.0");
      expect(result.claims.entra_subject).toBe("entra-user-1");
      expect(result.claims.aud).toBe("https://api.writerflow.app/web-session");
    }
  });

  it("a device access token is never valid as a web-session token, and vice versa", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { token: deviceToken } = await mintAccessToken(keys, {
      userId: "user-1",
      deviceId: "device-1",
      organizationId: "org-1",
      scope: "device"
    });
    const { token: webSessionToken } = await mintWebSessionToken(keys, {
      entraIssuer: "https://writerflow.ciamlogin.com/tenant-id/v2.0",
      entraSubject: "entra-user-1"
    });

    const deviceTokenAsWebSession = await verifyWebSessionToken(keys, deviceToken);
    expect(deviceTokenAsWebSession.ok).toBe(false);

    const webSessionAsDeviceToken = await verifyAccessToken(keys, webSessionToken);
    expect(webSessionAsDeviceToken.ok).toBe(false);
  });
});

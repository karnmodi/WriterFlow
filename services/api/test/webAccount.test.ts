import { describe, expect, it } from "vitest";
import { SignJWT, generateKeyPair } from "jose";
import {
  WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE,
  WRITERFLOW_WEB_ACCOUNT_TOKEN_TTL_SECONDS,
  WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE,
  WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS
} from "@writerflow/shared";
import { LocalDevSigningKeyProvider } from "../src/jwt/keys.js";
import {
  mintWebAccountToken,
  mintWebSessionBridgeFromAccount,
  verifyWebAccountToken,
  verifyWebSessionToken
} from "../src/jwt/issuer.js";

describe("web-account token issuer (ADR-0013)", () => {
  it("mints a web-account token with distinct audience from device and pairing bridge", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { token, expiresIn } = await mintWebAccountToken(keys, {
      userId: "user-1",
      organizationId: "org-1",
      entraIssuer: "https://writerflow.ciamlogin.com/t/v2.0",
      entraSubject: "entra-subject-1",
      displayClaims: { name: "Karan", email: "karan@example.com" }
    });
    expect(expiresIn).toBe(WRITERFLOW_WEB_ACCOUNT_TOKEN_TTL_SECONDS);

    const verified = await verifyWebAccountToken(keys, token);
    expect(verified.ok).toBe(true);
    if (verified.ok) {
      expect(verified.claims.sub).toBe("user-1");
      expect(verified.claims.org_id).toBe("org-1");
      expect(verified.claims.aud).toBe(WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE);
      expect(verified.claims.entra_subject).toBe("entra-subject-1");
    }

    const asDevice = await verifyWebSessionToken(keys, token);
    expect(asDevice.ok).toBe(false);
  });

  it("bridges a web-account token to a short web-session token for pairing", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { token: accountToken } = await mintWebAccountToken(keys, {
      userId: "user-1",
      organizationId: "org-1",
      entraIssuer: "https://writerflow.ciamlogin.com/t/v2.0",
      entraSubject: "entra-subject-1"
    });
    const accountClaims = await verifyWebAccountToken(keys, accountToken);
    expect(accountClaims.ok).toBe(true);
    if (!accountClaims.ok) return;

    const { token: bridgeToken, expiresIn } = await mintWebSessionBridgeFromAccount(keys, accountClaims.claims);
    expect(expiresIn).toBe(WRITERFLOW_WEB_SESSION_TOKEN_TTL_SECONDS);

    const bridgeVerified = await verifyWebSessionToken(keys, bridgeToken);
    expect(bridgeVerified.ok).toBe(true);
    if (bridgeVerified.ok) {
      expect(bridgeVerified.claims.aud).toBe(WRITERFLOW_WEB_SESSION_TOKEN_AUDIENCE);
      expect(bridgeVerified.claims.entra_subject).toBe("entra-subject-1");
    }
  });

  it("rejects a web-account token signed by a different key", async () => {
    const keys = new LocalDevSigningKeyProvider();
    const { privateKey: otherPrivateKey } = await generateKeyPair("ES256", { extractable: true });
    const token = await new SignJWT({
      org_id: "org-1",
      entra_issuer: "https://writerflow.ciamlogin.com/t/v2.0",
      entra_subject: "entra-subject-1"
    })
      .setProtectedHeader({ alg: "ES256", kid: "other-kid" })
      .setIssuer("https://apiwriterflow.aviusolutions.com")
      .setAudience(WRITERFLOW_WEB_ACCOUNT_TOKEN_AUDIENCE)
      .setSubject("user-1")
      .setIssuedAt()
      .setExpirationTime("15m")
      .sign(otherPrivateKey);
    const result = await verifyWebAccountToken(keys, token);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("unknown_kid");
  });
});

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes } from "node:crypto";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { buildApp } from "../../src/app.js";
import { LocalDevSigningKeyProvider } from "../../src/jwt/keys.js";
import { EntraIdTokenVerifier } from "../../src/entra/verifier.js";
import { fakeConfig } from "../helpers/fakeConfig.js";

const MIGRATOR_URL =
  process.env["TEST_DATABASE_URL_MIGRATOR"] ??
  "postgres://writerflow_migrator:writerflow_migrator_dev_only@localhost:5432/writerflow";
const APP_URL =
  process.env["TEST_DATABASE_URL_APP"] ??
  "postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow";

const ISSUER = "https://writerflow.ciamlogin.com/tenant-id/v2.0";
const AUDIENCE = "web-app-client-id";

async function probeReachable(connectionString: string): Promise<boolean> {
  const pool = new pg.Pool({ connectionString, connectionTimeoutMillis: 1500 });
  try {
    await pool.query("SELECT 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const dbAvailable = await probeReachable(MIGRATOR_URL);

describe.skipIf(!dbAvailable)("web account routes against real Postgres", () => {
  let appPool: pg.Pool;
  const keys = new LocalDevSigningKeyProvider();
  let app: Awaited<ReturnType<typeof buildApp>>;
  let idToken: string;
  let subject: string;

  beforeAll(async () => {
    appPool = new pg.Pool({ connectionString: APP_URL });
    const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
    const publicJwk = await exportJWK(publicKey);
    publicJwk.kid = "test-kid";
    publicJwk.alg = "ES256";
    subject = `web-account-${randomBytes(4).toString("hex")}`;
    idToken = await new SignJWT({ email: `${subject}@example.com`, name: "Web User" })
      .setProtectedHeader({ alg: "ES256", kid: "test-kid" })
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setSubject(subject)
      .setIssuedAt()
      .setExpirationTime("10m")
      .sign(privateKey);

    const entraVerifier = EntraIdTokenVerifier.local({ keys: [publicJwk] }, ISSUER, AUDIENCE);
    app = buildApp({ config: fakeConfig(), pool: appPool, signingKeys: keys, entraVerifier });
  });

  afterAll(async () => {
    await app.close();
    await appPool.end();
  });

  it("POST /web-account/token provisions a user and GET /web/me returns the snapshot", async () => {
    const mintResponse = await app.inject({
      method: "POST",
      url: "/web-account/token",
      payload: { idToken }
    });
    expect(mintResponse.statusCode).toBe(200);
    const mintBody = mintResponse.json() as { accessToken: string; created: boolean };
    expect(mintBody.created).toBe(true);

    const meResponse = await app.inject({
      method: "GET",
      url: "/web/me",
      headers: { authorization: `Bearer ${mintBody.accessToken}` }
    });
    expect(meResponse.statusCode).toBe(200);
    const me = meResponse.json() as { email: string | null; displayName: string | null; entitlement: { plan: string } };
    expect(me.email).toBe(`${subject}@example.com`);
    expect(me.displayName).toBe("Web User");
    expect(me.entitlement.plan).toBe("free");
  });

  it("POST /web-session/bridge mints a pairing token from a web-account bearer", async () => {
    const mintResponse = await app.inject({
      method: "POST",
      url: "/web-account/token",
      payload: { idToken }
    });
    const { accessToken } = mintResponse.json() as { accessToken: string };

    const bridgeResponse = await app.inject({
      method: "POST",
      url: "/web-session/bridge",
      headers: { authorization: `Bearer ${accessToken}` }
    });
    expect(bridgeResponse.statusCode).toBe(200);
    const bridge = bridgeResponse.json() as { accessToken: string; expiresIn: number };
    expect(bridge.expiresIn).toBe(300);
    expect(bridge.accessToken.split(".")).toHaveLength(3);
  });

  it("GET /web/me rejects a device access token", async () => {
    const { mintAccessToken } = await import("../../src/jwt/issuer.js");
    const { token } = await mintAccessToken(keys, {
      userId: "user-x",
      deviceId: "device-x",
      organizationId: "org-x",
      scope: "device"
    });
    const response = await app.inject({
      method: "GET",
      url: "/web/me",
      headers: { authorization: `Bearer ${token}` }
    });
    expect(response.statusCode).toBe(401);
  });
});

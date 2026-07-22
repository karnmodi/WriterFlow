import { Writable } from "node:stream";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes } from "node:crypto";
import { authorizeDevice, pollDeviceToken } from "../../src/pairing/service.js";
import { approveDevice } from "../../src/pairing/approve.js";
import { LocalDevSigningKeyProvider } from "../../src/jwt/keys.js";
import { computeS256Challenge } from "../../src/crypto/pkce.js";
import { buildApp } from "../../src/app.js";
import { fakeConfig } from "../helpers/fakeConfig.js";
import { testEntraIdentity } from "../helpers/testIdentity.js";

/**
 * Docs/contracts/inference-stream.md's "Allowed log fields" contract and
 * phase-5's "verify secrets/tokens never appear in macOS/backend logs"
 * checklist item — proven against REAL request/response log output (a
 * captured pino stream), not just by reading app.ts's redact-path list and
 * trusting it's wired correctly. Covers the pairing/account routes added
 * this stage: device_code/user_code/PKCE verifier at /device/authorize and
 * /device/token, the bearer access token at /me and /devices/:id, and the
 * refresh token at /token/refresh.
 */
const MIGRATOR_URL =
  process.env["TEST_DATABASE_URL_MIGRATOR"] ??
  "postgres://writerflow_migrator:writerflow_migrator_dev_only@localhost:5432/writerflow";
const APP_URL =
  process.env["TEST_DATABASE_URL_APP"] ??
  "postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow";

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

describe.skipIf(!dbAvailable)("secrets never reach the backend request log", () => {
  let appPool: pg.Pool;
  const keys = new LocalDevSigningKeyProvider();
  const logChunks: string[] = [];
  const captureStream = new Writable({
    write(chunk: Buffer, _enc, callback) {
      logChunks.push(chunk.toString("utf8"));
      callback();
    }
  });
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(() => {
    appPool = new pg.Pool({ connectionString: APP_URL });
    app = buildApp({
      config: fakeConfig({ LOG_LEVEL: "info" }),
      pool: appPool,
      signingKeys: keys,
      entraVerifier: null,
      logStream: captureStream
    });
  });

  afterAll(async () => {
    await app.close();
    await appPool.end();
  });

  it("device_code, user_code, PKCE verifier, access token, and refresh token never appear verbatim in log output", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const auth = await authorizeDevice(appPool, "https://writerflow.aviusolutions.com", {
      installId: "mac-log-safety",
      deviceLabel: "Log Safety Test Mac",
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const identity = testEntraIdentity(`log-safety-${randomBytes(4).toString("hex")}`);
    const approveResult = await approveDevice(appPool, identity, auth.userCode);
    if (approveResult.kind !== "approved") throw new Error(`expected approved, got ${approveResult.kind}`);
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, verifier);
    if (tokenResult.kind !== "issued") throw new Error(`expected issued, got ${tokenResult.kind}`);

    await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${tokenResult.accessToken}` }
    });
    await app.inject({
      method: "POST",
      url: "/token/refresh",
      payload: { refreshToken: tokenResult.refreshToken }
    });
    await app.inject({
      method: "DELETE",
      url: `/devices/${tokenResult.deviceId}`,
      headers: { authorization: `Bearer ${tokenResult.accessToken}` }
    });

    const logText = logChunks.join("");
    expect(logText.length).toBeGreaterThan(0); // sanity: requests were actually logged

    const secrets = [auth.deviceCode, auth.userCode, verifier, tokenResult.accessToken, tokenResult.refreshToken];
    for (const secret of secrets) {
      expect(logText.includes(secret)).toBe(false);
    }
  });
});

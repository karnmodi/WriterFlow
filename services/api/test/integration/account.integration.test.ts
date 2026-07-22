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

interface AccountSnapshotBody {
  userId: string;
  organizationId: string;
  displayName: string | null;
  email: string | null;
  device: { id: string; label: string | null; revoked: boolean; current: boolean };
  entitlement: { plan: string };
}

interface ErrorBody {
  code: string;
}

/**
 * GET /v2/me and DELETE /v2/devices/{id} — Docs/contracts/openapi.yaml —
 * against real Postgres via app.inject() (real HTTP request/response
 * handling, no real socket). Same rationale as every other integration
 * suite this stage: prove requireDeviceAuth's DB re-checks actually work,
 * not just that the code compiles against a mock.
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

describe.skipIf(!dbAvailable)("GET /me and DELETE /devices/:id against real Postgres", () => {
  let migratorPool: pg.Pool;
  let appPool: pg.Pool;
  const keys = new LocalDevSigningKeyProvider();
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(() => {
    migratorPool = new pg.Pool({ connectionString: MIGRATOR_URL });
    appPool = new pg.Pool({ connectionString: APP_URL });
    app = buildApp({ config: fakeConfig(), pool: appPool, signingKeys: keys, entraVerifier: null });
  });

  afterAll(async () => {
    await app.close();
    await migratorPool.end();
    await appPool.end();
  });

  async function pairNewDevice(subject: string, installId: string) {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const auth = await authorizeDevice(appPool, "https://writerflow.aviusolutions.com", {
      installId,
      deviceLabel: "Test Mac",
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const email = `${subject.replace(/[^a-zA-Z0-9_-]/g, "_")}@example.com`;
    const identity = testEntraIdentity(subject, {
      displayName: "Karan Singh",
      email,
      displayClaims: { name: "Karan Singh", email }
    });
    const approveResult = await approveDevice(appPool, identity, auth.userCode);
    if (approveResult.kind !== "approved") throw new Error(`expected approved, got ${approveResult.kind}`);
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, verifier);
    if (tokenResult.kind !== "issued") throw new Error(`expected issued, got ${tokenResult.kind}`);
    return {
      accessToken: tokenResult.accessToken,
      deviceId: tokenResult.deviceId,
      userId: approveResult.snapshot.userId,
      organizationId: approveResult.snapshot.organizationId,
      email
    };
  }

  it("GET /me returns the authenticated account snapshot with the device label persisted from pairing", async () => {
    const session = await pairNewDevice(`me-user-${randomBytes(4).toString("hex")}`, "mac-me-1");
    const response = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${session.accessToken}` }
    });
    expect(response.statusCode).toBe(200);
    const body = response.json<AccountSnapshotBody>();
    expect(body.userId).toBe(session.userId);
    expect(body.organizationId).toBe(session.organizationId);
    expect(body.device.id).toBe(session.deviceId);
    expect(body.device.label).toBe("Test Mac");
    expect(body.device.revoked).toBe(false);
    expect(body.device.current).toBe(true);
    expect(body.displayName).toBe("Karan Singh");
    expect(body.email).toBe(session.email);
    expect(body.entitlement.plan).toBe("free");
  });

  it("GET /me without a bearer token returns 401 AUTH_REQUIRED", async () => {
    const response = await app.inject({ method: "GET", url: "/me" });
    expect(response.statusCode).toBe(401);
    expect(response.json<ErrorBody>().code).toBe("AUTH_REQUIRED");
  });

  it("GET /me with a garbage token returns 401 AUTH_INVALID", async () => {
    const response = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: "Bearer not-a-real-token" }
    });
    expect(response.statusCode).toBe(401);
    expect(response.json<ErrorBody>().code).toBe("AUTH_INVALID");
  });

  it("a device can revoke another device belonging to the same user", async () => {
    const subject = `revoke-user-${randomBytes(4).toString("hex")}`;
    const deviceA = await pairNewDevice(subject, "mac-A");
    const deviceB = await pairNewDevice(subject, "mac-B");
    expect(deviceA.userId).toBe(deviceB.userId);

    const revokeResponse = await app.inject({
      method: "DELETE",
      url: `/devices/${deviceA.deviceId}`,
      headers: { authorization: `Bearer ${deviceB.accessToken}` }
    });
    expect(revokeResponse.statusCode).toBe(204);

    // The revoked device's OWN token must now be rejected...
    const meAsRevoked = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${deviceA.accessToken}` }
    });
    expect(meAsRevoked.statusCode).toBe(401);
    expect(meAsRevoked.json<ErrorBody>().code).toBe("DEVICE_REVOKED");

    // ...but the OTHER device (the one that issued the revoke) still works.
    const meAsB = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${deviceB.accessToken}` }
    });
    expect(meAsB.statusCode).toBe(200);
  });

  it("revoking a device also invalidates its refresh token, not just future access tokens", async () => {
    const subject = `revoke-refresh-user-${randomBytes(4).toString("hex")}`;
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const auth = await authorizeDevice(appPool, "https://writerflow.aviusolutions.com", {
      installId: "mac-refresh-revoke",
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const identity = testEntraIdentity(subject, {
      displayName: "Karan Singh",
      email: `${subject}@example.com`,
      displayClaims: { name: "Karan Singh", email: `${subject}@example.com` }
    });
    const approveResult = await approveDevice(appPool, identity, auth.userCode);
    if (approveResult.kind !== "approved") throw new Error("expected approved");
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, verifier);
    if (tokenResult.kind !== "issued") throw new Error("expected issued");

    const revokeResponse = await app.inject({
      method: "DELETE",
      url: `/devices/${tokenResult.deviceId}`,
      headers: { authorization: `Bearer ${tokenResult.accessToken}` }
    });
    expect(revokeResponse.statusCode).toBe(204);

    const refreshResponse = await app.inject({
      method: "POST",
      url: "/token/refresh",
      payload: { refreshToken: tokenResult.refreshToken }
    });
    expect(refreshResponse.statusCode).toBe(401);
  });

  it("cannot revoke another user's device (404, not leaked as a different error)", async () => {
    const victim = await pairNewDevice(`victim-${randomBytes(4).toString("hex")}`, "mac-victim");
    const attacker = await pairNewDevice(`attacker-${randomBytes(4).toString("hex")}`, "mac-attacker");

    const response = await app.inject({
      method: "DELETE",
      url: `/devices/${victim.deviceId}`,
      headers: { authorization: `Bearer ${attacker.accessToken}` }
    });
    expect(response.statusCode).toBe(404);

    // Confirm the victim's device is untouched.
    const victimStillWorks = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${victim.accessToken}` }
    });
    expect(victimStillWorks.statusCode).toBe(200);
  });

  it("a disabled user's existing device is rejected by /me and by token refresh (closes the known gap)", async () => {
    const subject = `disabled-me-user-${randomBytes(4).toString("hex")}`;
    const session = await pairNewDevice(subject, "mac-disabled-me");
    await migratorPool.query(`UPDATE users SET status = 'disabled' WHERE id = $1`, [session.userId]);

    const meResponse = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${session.accessToken}` }
    });
    expect(meResponse.statusCode).toBe(403);
    expect(meResponse.json<ErrorBody>().code).toBe("AUTH_INVALID");
  });
});

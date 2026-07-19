import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes } from "node:crypto";
import { authorizeDevice, pollDeviceToken, rotateRefreshToken } from "../../src/pairing/service.js";
import { LocalDevSigningKeyProvider } from "../../src/jwt/keys.js";
import { verifyAccessToken } from "../../src/jwt/issuer.js";
import { computeS256Challenge } from "../../src/crypto/pkce.js";
import { hashToken } from "../../src/crypto/tokens.js";

/**
 * Exercises the device-token issuer against a REAL local Postgres — not
 * mocks — specifically to prove migration 010's RLS bootstrap-lookup fix
 * actually works when running as the unprivileged `writerflow_app` role,
 * the same role the deployed API connects as. A mock pool would hide
 * exactly the class of bug this test exists to catch.
 *
 * Requires `docker compose up -d postgres` + migrations applied first (see
 * README below / CI's `migrations` job). Skips cleanly if unreachable so it
 * never breaks `npm test` in environments without Docker.
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

describe.skipIf(!dbAvailable)("device pairing against real Postgres", () => {
  let migratorPool: pg.Pool;
  let appPool: pg.Pool;
  const keys = new LocalDevSigningKeyProvider();

  beforeAll(() => {
    migratorPool = new pg.Pool({ connectionString: MIGRATOR_URL });
    appPool = new pg.Pool({ connectionString: APP_URL });
  });

  afterAll(async () => {
    await migratorPool.end();
    await appPool.end();
  });

  async function seedApprovedDevice(userCode: string): Promise<{ deviceId: string; organizationId: string }> {
    const userRes = await migratorPool.query<{ id: string }>(
      `INSERT INTO users DEFAULT VALUES RETURNING id`
    );
    const userId = userRes.rows[0]?.id;
    if (!userId) throw new Error("failed to seed user");
    const orgRes = await migratorPool.query<{ id: string }>(
      `INSERT INTO organizations (kind, owner_user_id) VALUES ('personal', $1) RETURNING id`,
      [userId]
    );
    const organizationId = orgRes.rows[0]?.id;
    if (!organizationId) throw new Error("failed to seed organization");
    await migratorPool.query(
      `INSERT INTO organization_memberships (organization_id, user_id, role) VALUES ($1, $2, 'owner')`,
      [organizationId, userId]
    );
    const deviceRes = await migratorPool.query<{ id: string }>(
      `INSERT INTO devices (user_id, organization_id) VALUES ($1, $2) RETURNING id`,
      [userId, organizationId]
    );
    const deviceId = deviceRes.rows[0]?.id;
    if (!deviceId) throw new Error("failed to seed device");
    await migratorPool.query(
      `UPDATE device_authorizations SET status = 'approved', approved_device_id = $1, approved_at = now() WHERE user_code = $2`,
      [deviceId, userCode]
    );
    return { deviceId, organizationId };
  }

  /** Clears the rate-limit timestamp so the next poll in a test isn't rejected as slow_down — the interval check itself is covered separately below. */
  async function resetPollInterval(deviceCode: string): Promise<void> {
    await migratorPool.query(`UPDATE device_authorizations SET last_polled_at = NULL WHERE device_code_hash = $1`, [
      hashToken(deviceCode)
    ]);
  }

  it("completes authorize -> (simulated approve) -> token -> refresh -> reuse detection end to end", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);

    const authResult = await authorizeDevice(appPool, "https://writerflow.app", {
      installId: "install-1",
      deviceLabel: "Test Mac",
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    expect(authResult.userCode).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);

    const pendingBeforeApproval = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(pendingBeforeApproval).toEqual({ kind: "pending", status: "authorization_pending" });
    await resetPollInterval(authResult.deviceCode);

    const { deviceId } = await seedApprovedDevice(authResult.userCode);

    const wrongVerifierResult = await pollDeviceToken(appPool, keys, authResult.deviceCode, "wrong-verifier-wrong-verifier");
    expect(wrongVerifierResult).toEqual({ kind: "invalid_grant" });
    await resetPollInterval(authResult.deviceCode);

    const issued = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(issued.kind).toBe("issued");
    if (issued.kind !== "issued") throw new Error("expected issued");
    expect(issued.deviceId).toBe(deviceId);

    const verified = await verifyAccessToken(keys, issued.accessToken);
    expect(verified.ok).toBe(true);
    if (verified.ok) {
      expect(verified.claims.device_id).toBe(deviceId);
    }

    // device_code is single-use: replaying it must not mint a second token.
    const replay = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(replay).toEqual({ kind: "pending", status: "expired_token" });

    const rotated = await rotateRefreshToken(appPool, keys, issued.refreshToken);
    expect(rotated.kind).toBe("issued");
    if (rotated.kind !== "issued") throw new Error("expected issued");
    expect(rotated.refreshToken).not.toBe(issued.refreshToken);

    // Reuse detection: presenting the now-superseded original refresh token
    // must fail AND revoke the whole family, invalidating the just-rotated
    // token too.
    const reuseAttempt = await rotateRefreshToken(appPool, keys, issued.refreshToken);
    expect(reuseAttempt).toEqual({ kind: "invalid" });

    const rotatedTokenAfterReuse = await rotateRefreshToken(appPool, keys, rotated.refreshToken);
    expect(rotatedTokenAfterReuse).toEqual({ kind: "invalid" });
  });

  it("rate-limits polling faster than the advertised interval (slow_down)", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const authResult = await authorizeDevice(
      appPool,
      "https://writerflow.app",
      { installId: "install-3", deviceLabel: null, codeChallenge: challenge, codeChallengeMethod: "S256" },
      { intervalSeconds: 5 }
    );
    const first = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(first).toEqual({ kind: "pending", status: "authorization_pending" });
    const second = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(second).toEqual({ kind: "pending", status: "slow_down" });
  });

  it("expires a device_code past its expires_at, even while still pending", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const authResult = await authorizeDevice(appPool, "https://writerflow.app", {
      installId: "install-4",
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    await migratorPool.query(
      `UPDATE device_authorizations SET expires_at = now() - interval '1 second' WHERE device_code_hash = $1`,
      [hashToken(authResult.deviceCode)]
    );
    const result = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(result).toEqual({ kind: "pending", status: "expired_token" });
  });

  it("rejects tokens for a revoked device", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const authResult = await authorizeDevice(appPool, "https://writerflow.app", {
      installId: "install-2",
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const { deviceId } = await seedApprovedDevice(authResult.userCode);
    await migratorPool.query(`UPDATE devices SET revoked_at = now() WHERE id = $1`, [deviceId]);

    const result = await pollDeviceToken(appPool, keys, authResult.deviceCode, verifier);
    expect(result).toEqual({ kind: "invalid_grant" });
  });

  it(
    "proves RLS still blocks a direct, non-bootstrap devices read as writerflow_app",
    async () => {
      const client = await appPool.connect();
      try {
        await client.query("BEGIN");
        // No tenant context, no bootstrap flag — RLS (migration 008) must
        // deny every row, proving the app role has no ambient access outside
        // the two explicit escape hatches (withTenantContext,
        // withDeviceBootstrapLookup).
        const { rows } = await client.query("SELECT * FROM devices");
        expect(rows).toHaveLength(0);
        await client.query("ROLLBACK");
      } finally {
        client.release();
      }
    }
  );
});

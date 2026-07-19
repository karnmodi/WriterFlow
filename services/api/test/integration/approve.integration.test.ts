import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes } from "node:crypto";
import { authorizeDevice, pollDeviceToken } from "../../src/pairing/service.js";
import { approveDevice } from "../../src/pairing/approve.js";
import { LocalDevSigningKeyProvider } from "../../src/jwt/keys.js";
import { computeS256Challenge } from "../../src/crypto/pkce.js";
import type { EntraIdentity } from "../../src/entra/verifier.js";

/**
 * POST /v2/device/approve's provisioning logic (services/api/src/pairing/
 * approve.ts), exercised against real Postgres as the writerflow_app role —
 * same rationale as pairing.integration.test.ts. Skips cleanly without
 * Docker Postgres.
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

describe.skipIf(!dbAvailable)("device approve provisioning against real Postgres", () => {
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

  async function newAuthorizedDevice(installId: string) {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const authResult = await authorizeDevice(appPool, "https://writerflow.app", {
      installId,
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    return { ...authResult, verifier };
  }

  it("provisions a brand-new identity: user, org, membership, device, privacy, free-alpha entitlement", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: `new-user-${randomBytes(4).toString("hex")}` };
    const auth = await newAuthorizedDevice("mac-1");

    const result = await approveDevice(appPool, identity, auth.userCode);
    expect(result.kind).toBe("approved");
    if (result.kind !== "approved") throw new Error("expected approved");

    expect(result.snapshot.entitlement).toEqual({
      plan: "free",
      monthlyUnitsIncluded: 500,
      monthlyUnitsUsed: 0,
      features: ["auto_write"]
    });
    expect(result.snapshot.privacy).toEqual({ personalizationSyncEnabled: false, consentVersion: "1" });
    expect(result.snapshot.device.current).toBe(true);
    expect(result.snapshot.device.revoked).toBe(false);

    // The full chain works end to end: the now-approved device_code issues a real token.
    // Deliberately reuses the same pooled connection pattern as the rest of
    // the suite — this exact sequence (a withTenantContext call followed by
    // a withDeviceBootstrapLookup call on a connection the pool may reuse)
    // is what caught the current_tenant_id() empty-string bug fixed in
    // migration 008.
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, auth.verifier);
    expect(tokenResult.kind).toBe("issued");
    if (tokenResult.kind === "issued") {
      expect(tokenResult.deviceId).toBe(result.snapshot.device.id);
    }
  });

  it("is idempotent: re-approving the same already-approved user_code returns the same snapshot, no duplicate device", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: `retry-user-${randomBytes(4).toString("hex")}` };
    const auth = await newAuthorizedDevice("mac-retry");

    const first = await approveDevice(appPool, identity, auth.userCode);
    const second = await approveDevice(appPool, identity, auth.userCode);
    expect(first).toEqual(second);
  });

  it("a returning identity reuses its existing user/organization but gets a new device", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: `returning-user-${randomBytes(4).toString("hex")}` };

    const firstAuth = await newAuthorizedDevice("mac-A");
    const first = await approveDevice(appPool, identity, firstAuth.userCode);
    expect(first.kind).toBe("approved");
    if (first.kind !== "approved") throw new Error("expected approved");

    const secondAuth = await newAuthorizedDevice("mac-B");
    const second = await approveDevice(appPool, identity, secondAuth.userCode);
    expect(second.kind).toBe("approved");
    if (second.kind !== "approved") throw new Error("expected approved");

    expect(second.snapshot.userId).toBe(first.snapshot.userId);
    expect(second.snapshot.organizationId).toBe(first.snapshot.organizationId);
    expect(second.snapshot.device.id).not.toBe(first.snapshot.device.id);
  });

  it("rejects a returning identity whose account is disabled", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: `disabled-user-${randomBytes(4).toString("hex")}` };
    const firstAuth = await newAuthorizedDevice("mac-disable-1");
    const first = await approveDevice(appPool, identity, firstAuth.userCode);
    if (first.kind !== "approved") throw new Error("expected approved");

    await migratorPool.query(`UPDATE users SET status = 'disabled' WHERE id = $1`, [first.snapshot.userId]);

    const secondAuth = await newAuthorizedDevice("mac-disable-2");
    const second = await approveDevice(appPool, identity, secondAuth.userCode);
    expect(second).toEqual({ kind: "account_disabled" });
  });

  it("rejects an unknown user_code", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: "no-such-flow" };
    const result = await approveDevice(appPool, identity, "ZZZZ-ZZZZ");
    expect(result).toEqual({ kind: "invalid_user_code" });
  });

  it("rejects an expired user_code", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: "expired-flow-user" };
    const auth = await newAuthorizedDevice("mac-expired");
    await migratorPool.query(
      `UPDATE device_authorizations SET expires_at = now() - interval '1 second' WHERE user_code = $1`,
      [auth.userCode]
    );
    const result = await approveDevice(appPool, identity, auth.userCode);
    expect(result).toEqual({ kind: "invalid_user_code" });
  });

  it("proves the newly created organization is RLS-invisible under a different/no tenant context", async () => {
    const identity: EntraIdentity = { issuer: "https://writerflow.ciamlogin.com/t/v2.0", subject: `isolated-user-${randomBytes(4).toString("hex")}` };
    const auth = await newAuthorizedDevice("mac-isolated");
    const result = await approveDevice(appPool, identity, auth.userCode);
    if (result.kind !== "approved") throw new Error("expected approved");

    const client = await appPool.connect();
    try {
      await client.query("BEGIN");
      const rows = await client.query("SELECT * FROM organizations WHERE id = $1", [result.snapshot.organizationId]);
      expect(rows.rows).toHaveLength(0);
      await client.query("ROLLBACK");
    } finally {
      client.release();
    }
  });
});

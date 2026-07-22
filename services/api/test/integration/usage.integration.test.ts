import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes, randomUUID } from "node:crypto";
import { authorizeDevice, pollDeviceToken } from "../../src/pairing/service.js";
import { approveDevice } from "../../src/pairing/approve.js";
import { LocalDevSigningKeyProvider } from "../../src/jwt/keys.js";
import { computeS256Challenge } from "../../src/crypto/pkce.js";
import { testEntraIdentity } from "../helpers/testIdentity.js";
import {
  commitInferenceRequest,
  reserveInferenceRequest,
  transitionState
} from "../../src/inference/accounting.js";
import { getCurrentUsage } from "../../src/account/usage.js";

const MIGRATOR_URL =
  process.env["TEST_DATABASE_URL_MIGRATOR"] ??
  "postgres://writerflow_migrator:writerflow_migrator_dev_only@localhost:5432/writerflow";
const APP_URL =
  process.env["TEST_DATABASE_URL_APP"] ?? "postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow";

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

describe.skipIf(!dbAvailable)("GET /v2/usage/current data path against real Postgres", () => {
  let migratorPool: pg.Pool;
  let appPool: pg.Pool;
  const keys = new LocalDevSigningKeyProvider();

  beforeAll(async () => {
    migratorPool = new pg.Pool({ connectionString: MIGRATOR_URL });
    appPool = new pg.Pool({ connectionString: APP_URL });
    await migratorPool.query(`
      INSERT INTO pricing_versions (version_label, effective_at, conversion)
      VALUES ('alpha-flat-v1', now(), '{"flatUnitsPerRequest": 1}'::jsonb)
      ON CONFLICT (version_label) DO NOTHING
    `);
  });

  afterAll(async () => {
    await migratorPool.end();
    await appPool.end();
  });

  it("reflects committed usage in monthlyUnitsUsed", async () => {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const auth = await authorizeDevice(appPool, "https://writerflow.aviusolutions.com", {
      installId: `usage-${randomBytes(4).toString("hex")}`,
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const identity = testEntraIdentity(`usage-${randomBytes(4).toString("hex")}`);
    const approveResult = await approveDevice(appPool, identity, auth.userCode);
    if (approveResult.kind !== "approved") throw new Error("expected approved");
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, verifier);
    if (tokenResult.kind !== "issued") throw new Error("expected issued");

    const orgId = approveResult.snapshot.organizationId;
    const userId = approveResult.snapshot.userId;
    const deviceId = approveResult.snapshot.device.id;

    const reservation = await reserveInferenceRequest(appPool, {
      organizationId: orgId,
      userId,
      deviceId,
      operationId: randomUUID(),
      idempotencyKey: randomUUID(),
      mode: "explicit",
      requestedAction: "fixGrammar",
      route: "grammar_fast",
      promptVersion: "grammar@5.1.0"
    });
    await transitionState(appPool, orgId, reservation.requestId, "running");
    await commitInferenceRequest(appPool, {
      organizationId: orgId,
      userId,
      requestId: reservation.requestId,
      inputTokens: 10,
      outputTokens: 20
    });

    const usage = await getCurrentUsage(appPool, orgId);
    expect(usage.monthlyUnitsUsed).toBe(1);
    expect(usage.monthlyUnitsIncluded).toBe(500);
    expect(usage.resetAt).toMatch(/T/);
  });
});

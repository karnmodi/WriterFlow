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
  QuotaExceededError,
  releaseInferenceRequest,
  reserveInferenceRequest,
  transitionState
} from "../../src/inference/accounting.js";

/**
 * Stage 5.4 "Minimum accounting prerequisite" (services/api/src/inference/
 * accounting.ts), exercised against real Postgres as the writerflow_app
 * role — same rationale as approve.integration.test.ts. This is the one
 * piece of this stage worth an integration test despite the "don't focus on
 * testing" instruction for this development push: it's money/quota
 * correctness, exactly the kind of genuinely risky change that instruction
 * carves out an exception for. Skips cleanly without Docker Postgres.
 */
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

describe.skipIf(!dbAvailable)("Stage 5.4 inference accounting against real Postgres", () => {
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

  async function provisionAccount(label: string): Promise<{ organizationId: string; userId: string; deviceId: string }> {
    const verifier = randomBytes(32).toString("base64url");
    const challenge = computeS256Challenge(verifier);
    const auth = await authorizeDevice(appPool, "https://writerflow.app", {
      installId: `acct-${label}-${randomBytes(4).toString("hex")}`,
      deviceLabel: null,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    });
    const identity = testEntraIdentity(`acct-${label}-${randomBytes(4).toString("hex")}`);
    const approveResult = await approveDevice(appPool, identity, auth.userCode);
    if (approveResult.kind !== "approved") throw new Error(`expected approved, got ${approveResult.kind}`);
    const tokenResult = await pollDeviceToken(appPool, keys, auth.deviceCode, verifier);
    if (tokenResult.kind !== "issued") throw new Error(`expected issued, got ${tokenResult.kind}`);
    return {
      organizationId: approveResult.snapshot.organizationId,
      userId: approveResult.snapshot.userId,
      deviceId: approveResult.snapshot.device.id
    };
  }

  it("reserve -> transition -> commit is transactional: request completes, ledger entry commits, balance debits", async () => {
    const account = await provisionAccount("commit");

    const reservation = await reserveInferenceRequest(appPool, {
      organizationId: account.organizationId,
      userId: account.userId,
      deviceId: account.deviceId,
      operationId: randomUUID(),
      idempotencyKey: randomUUID(),
      mode: "explicit",
      requestedAction: "fixGrammar",
      route: "grammar_fast",
      promptVersion: "grammar@5.1.0"
    });
    expect(reservation.reused).toBe(false);
    expect(reservation.state).toBe("reserved");

    await transitionState(appPool, account.organizationId, reservation.requestId, "running");
    await transitionState(appPool, account.organizationId, reservation.requestId, "streaming");

    const commitResult = await commitInferenceRequest(appPool, {
      organizationId: account.organizationId,
      userId: account.userId,
      requestId: reservation.requestId,
      inputTokens: 20,
      outputTokens: 22
    });
    expect(commitResult.usedUnits).toBe(1);
    expect(commitResult.remainingUnits).toBe(499);

    const row = await migratorPool.query<{ state: string }>(`SELECT state FROM inference_requests WHERE id = $1`, [
      reservation.requestId
    ]);
    expect(row.rows[0]?.state).toBe("completed");

    const reservationRow = await migratorPool.query<{ state: string }>(
      `SELECT state FROM quota_reservations WHERE inference_request_id = $1`,
      [reservation.requestId]
    );
    expect(reservationRow.rows[0]?.state).toBe("committed");

    const ledger = await migratorPool.query<{ status: string; billable_units: number; input_tokens: number; output_tokens: number }>(
      `SELECT status, billable_units, input_tokens, output_tokens FROM usage_ledger WHERE inference_request_id = $1`,
      [reservation.requestId]
    );
    expect(ledger.rows).toHaveLength(1);
    expect(ledger.rows[0]).toMatchObject({ status: "committed", billable_units: 1, input_tokens: 20, output_tokens: 22 });
  });

  it("reusing an Idempotency-Key returns the existing request instead of reserving twice", async () => {
    const account = await provisionAccount("idem");
    const idempotencyKey = randomUUID();
    const baseParams = {
      organizationId: account.organizationId,
      userId: account.userId,
      deviceId: account.deviceId,
      idempotencyKey,
      mode: "explicit" as const,
      requestedAction: "fixGrammar",
      route: "grammar_fast",
      promptVersion: "grammar@5.1.0"
    };

    const first = await reserveInferenceRequest(appPool, { ...baseParams, operationId: randomUUID() });
    const second = await reserveInferenceRequest(appPool, { ...baseParams, operationId: randomUUID() });
    expect(first.reused).toBe(false);
    expect(second.reused).toBe(true);
    expect(second.requestId).toBe(first.requestId);

    const count = await migratorPool.query<{ count: string }>(
      `SELECT count(*) FROM inference_requests WHERE user_id = $1 AND idempotency_key = $2`,
      [account.userId, idempotencyKey]
    );
    expect(Number(count.rows[0]?.count)).toBe(1);
  });

  it("releasing on failure debits nothing and leaves the reservation released", async () => {
    const account = await provisionAccount("release");
    const reservation = await reserveInferenceRequest(appPool, {
      organizationId: account.organizationId,
      userId: account.userId,
      deviceId: account.deviceId,
      operationId: randomUUID(),
      idempotencyKey: randomUUID(),
      mode: "explicit",
      requestedAction: "fixGrammar",
      route: "grammar_fast",
      promptVersion: "grammar@5.1.0"
    });

    await releaseInferenceRequest(appPool, account.organizationId, reservation.requestId, "failed");

    const row = await migratorPool.query<{ state: string }>(`SELECT state FROM inference_requests WHERE id = $1`, [
      reservation.requestId
    ]);
    expect(row.rows[0]?.state).toBe("failed");

    const reservationRow = await migratorPool.query<{ state: string }>(
      `SELECT state FROM quota_reservations WHERE inference_request_id = $1`,
      [reservation.requestId]
    );
    expect(reservationRow.rows[0]?.state).toBe("released");

    const ledger = await migratorPool.query<{ count: string }>(`SELECT count(*) FROM usage_ledger WHERE inference_request_id = $1`, [
      reservation.requestId
    ]);
    expect(Number(ledger.rows[0]?.count)).toBe(0);

    // Releasing twice must be a no-op, not an error — a second disconnect
    // after the reservation is already terminal is expected, not exceptional.
    await expect(releaseInferenceRequest(appPool, account.organizationId, reservation.requestId, "failed")).resolves.toBeUndefined();
  });

  it("blocks reservation once the monthly allowance is exhausted, and reserves nothing when it does", async () => {
    const account = await provisionAccount("quota");
    const now = new Date();
    const periodStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString().slice(0, 10);
    const periodEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString().slice(0, 10);
    await migratorPool.query(
      `INSERT INTO usage_balances (organization_id, period_start, period_end, used_units, allowance_units)
       VALUES ($1, $2, $3, 500, 500)`,
      [account.organizationId, periodStart, periodEnd]
    );

    await expect(
      reserveInferenceRequest(appPool, {
        organizationId: account.organizationId,
        userId: account.userId,
        deviceId: account.deviceId,
        operationId: randomUUID(),
        idempotencyKey: randomUUID(),
        mode: "explicit",
        requestedAction: "fixGrammar",
        route: "grammar_fast",
        promptVersion: "grammar@5.1.0"
      })
    ).rejects.toBeInstanceOf(QuotaExceededError);

    const row = await migratorPool.query<{ count: string }>(`SELECT count(*) FROM inference_requests WHERE organization_id = $1`, [
      account.organizationId
    ]);
    expect(Number(row.rows[0]?.count)).toBe(0);
  });
});

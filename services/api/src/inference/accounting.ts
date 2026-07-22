import type pg from "pg";
import { OPERATION_STATE_TRANSITIONS, type OperationState } from "@writerflow/shared";
import { withTenantContext } from "../db.js";
import { ApiError } from "../errors.js";
import { FREE_ALPHA_MONTHLY_UNITS } from "../pairing/snapshot.js";

/**
 * Stage 5.4 "Minimum accounting prerequisite": one transactional reserve at
 * request start, one transactional commit-or-release at request end — no
 * path through routes/inference.ts may skip either half
 * (Docs/contracts/inference-stream.md's canonical state machine).
 *
 * Pricing is a flat placeholder (migration 012) until Stage 5.5's logical
 * route configuration and a real provider exist; only the transactional
 * discipline here is meant to be durable, not the specific unit cost.
 */

const ALPHA_PRICING_VERSION_LABEL = "alpha-flat-v1";
const FLAT_UNITS_PER_REQUEST = 1;

export class QuotaExceededError extends ApiError {
  constructor() {
    super("QUOTA_EXCEEDED", 402, "Monthly usage limit reached.");
  }
}

export interface ReserveInferenceRequestParams {
  organizationId: string;
  userId: string;
  deviceId: string;
  operationId: string;
  idempotencyKey: string;
  retryOf?: string | null;
  mode: "explicit" | "auto";
  requestedAction: string | null;
  route: string;
  promptVersion: string;
}

export interface ReservedInferenceRequest {
  requestId: string;
  state: OperationState;
  /** True when `idempotencyKey` matched an existing request — the caller
   * must not reserve quota or call the provider again, only replay the
   * final/current state (Docs/contracts/inference-stream.md "Retry and
   * idempotency rules"). */
  reused: boolean;
}

export interface CommitInferenceRequestParams {
  organizationId: string;
  userId: string;
  requestId: string;
  inputTokens: number;
  outputTokens: number;
}

export interface CommitResult {
  usedUnits: number;
  remainingUnits: number;
}

function currentPeriod(now = new Date()): { start: string; end: string } {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

/** Fail-fast check, not a dynamic creator — pricing versions are seeded only
 * by migration (append-only table), never minted by application code. */
async function requirePricingVersionId(client: pg.PoolClient): Promise<string> {
  const result = await client.query<{ id: string }>(`SELECT id FROM pricing_versions WHERE version_label = $1`, [
    ALPHA_PRICING_VERSION_LABEL
  ]);
  const row = result.rows[0];
  if (!row) {
    throw new ApiError("INTERNAL_ERROR", 500, "No active pricing version is configured.");
  }
  return row.id;
}

async function getOrCreateUsageBalance(
  client: pg.PoolClient,
  organizationId: string,
  allowanceUnits: number
): Promise<{ usedUnits: number; allowanceUnits: number }> {
  const { start, end } = currentPeriod();
  const existing = await client.query<{ used_units: number; allowance_units: number }>(
    `SELECT used_units, allowance_units FROM usage_balances WHERE organization_id = $1 AND period_start = $2`,
    [organizationId, start]
  );
  if (existing.rows[0]) {
    return { usedUnits: existing.rows[0].used_units, allowanceUnits: existing.rows[0].allowance_units };
  }
  const inserted = await client.query<{ used_units: number; allowance_units: number }>(
    `INSERT INTO usage_balances (organization_id, period_start, period_end, used_units, allowance_units)
     VALUES ($1, $2, $3, 0, $4)
     ON CONFLICT (organization_id, period_start) DO UPDATE SET organization_id = EXCLUDED.organization_id
     RETURNING used_units, allowance_units`,
    [organizationId, start, end, allowanceUnits]
  );
  const row = inserted.rows[0];
  if (!row) throw new ApiError("INTERNAL_ERROR", 500, "usage_balances upsert returned no row.");
  return { usedUnits: row.used_units, allowanceUnits: row.allowance_units };
}

function assertTransition(requestId: string, from: OperationState, to: OperationState): void {
  if (!OPERATION_STATE_TRANSITIONS[from].includes(to)) {
    throw new ApiError("INTERNAL_ERROR", 500, `Illegal inference_requests transition for ${requestId}: ${from} -> ${to}`);
  }
}

/**
 * Creates the request row + a worst-case quota reservation in one
 * transaction, before any provider call — or, on an `idempotencyKey` replay,
 * returns the existing row untouched and reserves nothing new.
 */
export async function reserveInferenceRequest(
  pool: pg.Pool,
  params: ReserveInferenceRequestParams
): Promise<ReservedInferenceRequest> {
  return withTenantContext(pool, params.organizationId, async (client) => {
    const existing = await client.query<{ id: string; state: OperationState }>(
      `SELECT id, state FROM inference_requests WHERE user_id = $1 AND idempotency_key = $2`,
      [params.userId, params.idempotencyKey]
    );
    if (existing.rows[0]) {
      return { requestId: existing.rows[0].id, state: existing.rows[0].state, reused: true };
    }

    // Fail fast if pricing isn't seeded, before spending a reservation slot.
    await requirePricingVersionId(client);

    const balance = await getOrCreateUsageBalance(client, params.organizationId, FREE_ALPHA_MONTHLY_UNITS);
    const remaining = balance.allowanceUnits - balance.usedUnits;
    if (remaining < FLAT_UNITS_PER_REQUEST) {
      throw new QuotaExceededError();
    }

    const requestResult = await client.query<{ id: string; state: OperationState }>(
      `INSERT INTO inference_requests
         (organization_id, user_id, device_id, operation_id, idempotency_key, retry_of, mode, requested_action, route, prompt_version)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id, state`,
      [
        params.organizationId,
        params.userId,
        params.deviceId,
        params.operationId,
        params.idempotencyKey,
        params.retryOf ?? null,
        params.mode,
        params.requestedAction,
        params.route,
        params.promptVersion
      ]
    );
    const request = requestResult.rows[0];
    if (!request) throw new ApiError("INTERNAL_ERROR", 500, "inference_requests insert returned no row.");

    await client.query(
      `INSERT INTO quota_reservations (inference_request_id, organization_id, reserved_units, expires_at)
       VALUES ($1, $2, $3, now() + interval '5 minutes')`,
      [request.id, params.organizationId, FLAT_UNITS_PER_REQUEST]
    );

    return { requestId: request.id, state: request.state, reused: false };
  });
}

/**
 * Advances `inference_requests.state` under a row lock, rejecting any
 * transition not in `OPERATION_STATE_TRANSITIONS`. Callers use this for the
 * non-terminal `running`/`streaming` steps; `commitInferenceRequest` and
 * `releaseInferenceRequest` handle the terminal ones themselves so they can
 * do their ledger/balance writes in the same transaction as the state flip.
 */
export async function transitionState(
  pool: pg.Pool,
  organizationId: string,
  requestId: string,
  to: OperationState
): Promise<void> {
  await withTenantContext(pool, organizationId, async (client) => {
    const current = await client.query<{ state: OperationState }>(`SELECT state FROM inference_requests WHERE id = $1 FOR UPDATE`, [
      requestId
    ]);
    const row = current.rows[0];
    if (!row) throw new ApiError("INTERNAL_ERROR", 500, `inference_requests row ${requestId} vanished mid-request.`);
    assertTransition(requestId, row.state, to);
    await client.query(`UPDATE inference_requests SET state = $2 WHERE id = $1`, [requestId, to]);
  });
}

/**
 * Terminal success: commits the reservation, writes one `usage_ledger`
 * entry, debits `usage_balances`, and marks the request `completed` — all in
 * one transaction, so a crash between any two of those steps is impossible.
 */
export async function commitInferenceRequest(pool: pg.Pool, params: CommitInferenceRequestParams): Promise<CommitResult> {
  return withTenantContext(pool, params.organizationId, async (client) => {
    const current = await client.query<{ state: OperationState }>(`SELECT state FROM inference_requests WHERE id = $1 FOR UPDATE`, [
      params.requestId
    ]);
    const row = current.rows[0];
    if (!row) throw new ApiError("INTERNAL_ERROR", 500, `inference_requests row ${params.requestId} vanished mid-request.`);
    assertTransition(params.requestId, row.state, "completed");

    const pricingVersionId = await requirePricingVersionId(client);

    await client.query(`UPDATE quota_reservations SET state = 'committed' WHERE inference_request_id = $1 AND state = 'reserved'`, [
      params.requestId
    ]);
    await client.query(
      `INSERT INTO usage_ledger
         (inference_request_id, organization_id, user_id, stage, route, pricing_version_id, input_tokens, output_tokens, provider_cost_micros, billable_units, status)
       VALUES ($1, $2, $3, 'generator', 'grammar_fast', $4, $5, $6, 0, $7, 'committed')`,
      [params.requestId, params.organizationId, params.userId, pricingVersionId, params.inputTokens, params.outputTokens, FLAT_UNITS_PER_REQUEST]
    );
    const { start } = currentPeriod();
    const updated = await client.query<{ used_units: number; allowance_units: number }>(
      `UPDATE usage_balances SET used_units = used_units + $3 WHERE organization_id = $1 AND period_start = $2
       RETURNING used_units, allowance_units`,
      [params.organizationId, start, FLAT_UNITS_PER_REQUEST]
    );
    await client.query(`UPDATE inference_requests SET state = 'completed' WHERE id = $1`, [params.requestId]);

    const balance = updated.rows[0];
    if (!balance) throw new ApiError("INTERNAL_ERROR", 500, "usage_balances update returned no row.");
    return { usedUnits: balance.used_units, remainingUnits: Math.max(0, balance.allowance_units - balance.used_units) };
  });
}

/**
 * Terminal failure/cancellation: releases the reservation (no
 * `usage_ledger` entry — zero customer billable units, per
 * Docs/contracts/inference-stream.md) and marks the request accordingly.
 * A no-op, not an error, if the request is already terminal — a second
 * disconnect after completion, or a race between two release paths, is
 * expected, not exceptional.
 */
export async function releaseInferenceRequest(
  pool: pg.Pool,
  organizationId: string,
  requestId: string,
  outcome: "failed" | "cancelled"
): Promise<void> {
  await withTenantContext(pool, organizationId, async (client) => {
    const current = await client.query<{ state: OperationState }>(`SELECT state FROM inference_requests WHERE id = $1 FOR UPDATE`, [
      requestId
    ]);
    const row = current.rows[0];
    if (!row) return;
    if (!OPERATION_STATE_TRANSITIONS[row.state].includes(outcome)) return;

    await client.query(`UPDATE quota_reservations SET state = 'released' WHERE inference_request_id = $1 AND state = 'reserved'`, [
      requestId
    ]);
    await client.query(`UPDATE inference_requests SET state = $2 WHERE id = $1`, [requestId, outcome]);
  });
}

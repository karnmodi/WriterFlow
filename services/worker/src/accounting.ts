import type pg from "pg";

export interface ReconciliationResult {
  expiredReservations: number;
  correctedBalances: number;
}

/** Ledger is authoritative; balances and expired reservations are repairable projections. */
export async function reconcileAccounting(pool: pg.Pool): Promise<ReconciliationResult> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query<{ acquired: boolean }>(
      `SELECT pg_try_advisory_xact_lock(hashtext('writerflow-accounting-reconciliation')) AS acquired`
    );
    if (!lock.rows[0]?.acquired) {
      await client.query("ROLLBACK");
      return { expiredReservations: 0, correctedBalances: 0 };
    }

    const expired = await client.query<{ inference_request_id: string }>(
      `UPDATE quota_reservations
       SET state = 'released'
       WHERE state = 'reserved' AND expires_at <= now()
       RETURNING inference_request_id`
    );
    if (expired.rows.length > 0) {
      await client.query(
        `UPDATE inference_requests
         SET state = 'failed'
         WHERE id = ANY($1::uuid[]) AND state IN ('reserved', 'running', 'streaming')`,
        [expired.rows.map((row) => row.inference_request_id)]
      );
    }

    const corrected = await client.query(
      `WITH authoritative AS (
         SELECT
           b.organization_id,
           b.period_start,
           COALESCE(sum(
             CASE ledger.status
               WHEN 'committed' THEN ledger.billable_units
               WHEN 'reversed' THEN -ledger.billable_units
             END
           ) FILTER (
             WHERE ledger.created_at >= b.period_start
               AND ledger.created_at < b.period_end
           ), 0)::integer AS used_units
         FROM usage_balances b
         LEFT JOIN usage_ledger ledger ON ledger.organization_id = b.organization_id
         GROUP BY b.organization_id, b.period_start
       )
       UPDATE usage_balances balance
       SET used_units = authoritative.used_units
       FROM authoritative
       WHERE balance.organization_id = authoritative.organization_id
         AND balance.period_start = authoritative.period_start
         AND balance.used_units IS DISTINCT FROM authoritative.used_units`
    );

    await client.query("COMMIT");
    return {
      expiredReservations: expired.rowCount ?? 0,
      correctedBalances: corrected.rowCount ?? 0
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

import type pg from "pg";

export interface OutboxEventRow {
  id: string;
  organization_id: string | null;
  event_type: string;
  payload: unknown;
  attempts: number;
}

/**
 * Claims up to `batchSize` due, undispatched events using SKIP LOCKED so
 * multiple worker replicas never claim the same row (V2-ARCHITECTURE.md
 * §14.1: "Process the PostgreSQL transactional outbox with a separately
 * scaled worker using lease/SKIP LOCKED semantics"). Dispatch and
 * reconciliation logic land in Stage 5.5; this is the claim primitive only.
 */
export async function claimDueOutboxBatch(
  client: pg.PoolClient,
  batchSize: number
): Promise<OutboxEventRow[]> {
  const result = await client.query<OutboxEventRow>(
    `UPDATE outbox_events
     SET status = 'processing', attempts = attempts + 1
     WHERE id IN (
       SELECT id FROM outbox_events
       WHERE status IN ('pending', 'failed') AND available_at <= now()
       ORDER BY available_at
       FOR UPDATE SKIP LOCKED
       LIMIT $1
     )
     RETURNING id, organization_id, event_type, payload, attempts`,
    [batchSize]
  );
  return result.rows;
}

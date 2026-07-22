import type pg from "pg";
import { withoutTenantContext } from "../db.js";

export type StripeEventInboxResult = "inserted" | "duplicate";

export interface StripeEventRecordInput {
  stripeEventId: string;
  eventType: string;
  payload: Record<string, unknown>;
}

/**
 * Idempotent webhook inbox write — V2-ARCHITECTURE.md §13: insert the unique
 * Stripe event ID in one transaction before returning 2xx; async processing
 * comes later (worker/outbox, Stage 7.2).
 */
export async function recordStripeEventInbox(
  pool: pg.Pool,
  input: StripeEventRecordInput
): Promise<StripeEventInboxResult> {
  return withoutTenantContext(pool, async (client) => {
    const result = await client.query<{ stripe_event_id: string }>(
      `INSERT INTO stripe_events (stripe_event_id, event_type, payload)
       VALUES ($1, $2, $3::jsonb)
       ON CONFLICT (stripe_event_id) DO NOTHING
       RETURNING stripe_event_id`,
      [input.stripeEventId, input.eventType, JSON.stringify(input.payload)]
    );
    return (result.rowCount ?? 0) > 0 ? "inserted" : "duplicate";
  });
}

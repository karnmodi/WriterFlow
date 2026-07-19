/** V2-ARCHITECTURE.md §8.2/§14.1 — worker polls with lease/SKIP LOCKED semantics. */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE outbox_events (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
      event_type text NOT NULL,
      payload jsonb NOT NULL,
      status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'dispatched', 'failed')),
      attempts integer NOT NULL DEFAULT 0,
      available_at timestamptz NOT NULL DEFAULT now(),
      dispatched_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`
    CREATE INDEX outbox_events_poll_idx ON outbox_events (available_at)
    WHERE status IN ('pending', 'failed');
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS outbox_events;`);
};

/**
 * V2-ARCHITECTURE.md §8.3 + Stage 5.4's minimum accounting prerequisite.
 * No text columns anywhere here — request/output content never lands in
 * PostgreSQL (ephemeral-by-default, V2-ARCHITECTURE.md §7.3).
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE inference_requests (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES organizations(id),
      user_id uuid NOT NULL REFERENCES users(id),
      device_id uuid NOT NULL REFERENCES devices(id),
      operation_id uuid NOT NULL,
      idempotency_key uuid NOT NULL,
      retry_of uuid REFERENCES inference_requests(id),
      mode text NOT NULL CHECK (mode IN ('explicit', 'auto')),
      requested_action text CHECK (
        requested_action IS NULL
        OR requested_action IN ('elaborate', 'formal', 'casual', 'fixGrammar', 'reply', 'custom', 'promptBuilder')
      ),
      intent text,
      route text,
      state text NOT NULL DEFAULT 'reserved' CHECK (
        state IN ('reserved', 'running', 'streaming', 'completed', 'failed', 'cancelled')
      ),
      prompt_version text,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (user_id, idempotency_key)
    );
  `);
  pgm.sql(`CREATE INDEX inference_requests_organization_id_idx ON inference_requests (organization_id);`);
  pgm.sql(`CREATE INDEX inference_requests_device_id_idx ON inference_requests (device_id);`);
  pgm.sql(`CREATE INDEX inference_requests_state_idx ON inference_requests (state);`);
  pgm.sql(`
    CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
    BEGIN
      NEW.updated_at = now();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
  `);
  pgm.sql(`
    CREATE TRIGGER inference_requests_set_updated_at
    BEFORE UPDATE ON inference_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  `);

  pgm.sql(`
    CREATE TABLE quota_reservations (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      inference_request_id uuid NOT NULL REFERENCES inference_requests(id),
      organization_id uuid NOT NULL REFERENCES organizations(id),
      reserved_units integer NOT NULL CHECK (reserved_units >= 0),
      state text NOT NULL DEFAULT 'reserved' CHECK (state IN ('reserved', 'committed', 'released')),
      expires_at timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX quota_reservations_inference_request_id_idx ON quota_reservations (inference_request_id);`);
  pgm.sql(`CREATE INDEX quota_reservations_org_state_idx ON quota_reservations (organization_id, state);`);
  pgm.sql(`
    CREATE UNIQUE INDEX quota_reservations_one_open_per_request
    ON quota_reservations (inference_request_id)
    WHERE state = 'reserved';
  `);
  pgm.sql(`
    CREATE TRIGGER quota_reservations_set_updated_at
    BEFORE UPDATE ON quota_reservations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS quota_reservations;`);
  pgm.sql(`DROP TABLE IF EXISTS inference_requests;`);
  pgm.sql(`DROP FUNCTION IF EXISTS set_updated_at();`);
};

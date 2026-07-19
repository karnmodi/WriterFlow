/**
 * WriterFlow device-token issuer (ADR-0012) data model, Stage 5.2.
 *
 * device_authorizations backs POST /v2/device/authorize + /v2/device/token
 * (Docs/contracts/openapi.yaml DeviceAuthorizeRequest/Response,
 * DeviceTokenRequest/Response/Pending). device_code is stored hashed (it is
 * bearer-like once combined with the PKCE verifier); user_code is stored
 * plaintext — it is short/human-typed by design and rate-limit protected at
 * APIM (infra/apim/pairing-operations-policy.xml), not a secret on its own.
 *
 * refresh_tokens replaces the refresh_token_hash/refresh_token_family_id
 * columns migration 003 put directly on `devices` — proper rotation +
 * reuse-detection (V2-ARCHITECTURE.md §5.1 step 8, Docs/v2-threat-model.md)
 * needs per-token history, not just "the current hash", so a stale
 * (already-rotated) token presented again can be recognized and the whole
 * family revoked rather than just rejected as unrecognized.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE device_authorizations (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      device_code_hash text NOT NULL UNIQUE,
      user_code text NOT NULL UNIQUE,
      install_id text NOT NULL,
      device_label text,
      code_challenge text NOT NULL,
      code_challenge_method text NOT NULL CHECK (code_challenge_method = 'S256'),
      status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied', 'consumed', 'expired')),
      approved_device_id uuid REFERENCES devices(id),
      approved_at timestamptz,
      last_polled_at timestamptz,
      interval_seconds integer NOT NULL DEFAULT 5 CHECK (interval_seconds > 0),
      expires_at timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      CHECK (status != 'approved' OR approved_device_id IS NOT NULL)
    );
  `);
  pgm.sql(`CREATE INDEX device_authorizations_status_idx ON device_authorizations (status);`);

  pgm.sql(`
    CREATE TABLE refresh_tokens (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      family_id uuid NOT NULL,
      token_hash text NOT NULL UNIQUE,
      superseded_at timestamptz,
      revoked_at timestamptz,
      expires_at timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX refresh_tokens_device_id_idx ON refresh_tokens (device_id);`);
  pgm.sql(`CREATE INDEX refresh_tokens_family_id_idx ON refresh_tokens (family_id);`);
  pgm.sql(`
    CREATE UNIQUE INDEX refresh_tokens_one_active_per_family
    ON refresh_tokens (family_id)
    WHERE superseded_at IS NULL AND revoked_at IS NULL;
  `);

  pgm.sql(`ALTER TABLE devices DROP COLUMN refresh_token_hash;`);
  pgm.sql(`ALTER TABLE devices DROP COLUMN refresh_token_family_id;`);

  pgm.sql(`GRANT SELECT, INSERT, UPDATE, DELETE ON device_authorizations TO writerflow_app;`);
  pgm.sql(`GRANT SELECT, INSERT, UPDATE, DELETE ON refresh_tokens TO writerflow_app;`);
};

exports.down = (pgm) => {
  pgm.sql(`ALTER TABLE devices ADD COLUMN refresh_token_family_id uuid NOT NULL DEFAULT gen_random_uuid();`);
  pgm.sql(`ALTER TABLE devices ADD COLUMN refresh_token_hash text;`);
  pgm.sql(`DROP TABLE IF EXISTS refresh_tokens;`);
  pgm.sql(`DROP TABLE IF EXISTS device_authorizations;`);
};

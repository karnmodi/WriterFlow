/** V2-ARCHITECTURE.md §8.1 devices/privacy_preferences. */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE devices (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      install_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
      refresh_token_family_id uuid NOT NULL DEFAULT gen_random_uuid(),
      refresh_token_hash text,
      last_token_issued_at timestamptz,
      last_seen_at timestamptz,
      revoked_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX devices_user_id_idx ON devices (user_id);`);
  pgm.sql(`CREATE INDEX devices_organization_id_idx ON devices (organization_id);`);
  pgm.sql(`CREATE INDEX devices_active_idx ON devices (user_id) WHERE revoked_at IS NULL;`);

  pgm.sql(`
    CREATE TABLE privacy_preferences (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      sync_enabled boolean NOT NULL DEFAULT false,
      training_consent boolean NOT NULL DEFAULT false,
      retention_mode text NOT NULL DEFAULT 'ephemeral' CHECK (retention_mode IN ('ephemeral')),
      consent_version integer NOT NULL DEFAULT 1,
      consented_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX privacy_preferences_organization_id_idx ON privacy_preferences (organization_id);`);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS privacy_preferences;`);
  pgm.sql(`DROP TABLE IF EXISTS devices;`);
};

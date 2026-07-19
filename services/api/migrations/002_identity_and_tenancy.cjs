/** V2-ARCHITECTURE.md §8.1. */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE users (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'deleted')),
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);

  pgm.sql(`
    CREATE TABLE auth_identities (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      issuer text NOT NULL,
      subject text NOT NULL,
      display_claims jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (issuer, subject)
    );
  `);
  pgm.sql(`CREATE INDEX auth_identities_user_id_idx ON auth_identities (user_id);`);

  pgm.sql(`
    CREATE TABLE organizations (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      kind text NOT NULL CHECK (kind IN ('personal', 'team')),
      status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
      owner_user_id uuid NOT NULL REFERENCES users(id),
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX organizations_owner_user_id_idx ON organizations (owner_user_id);`);

  pgm.sql(`
    CREATE TABLE organization_memberships (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role text NOT NULL CHECK (role IN ('owner', 'member')),
      status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (organization_id, user_id)
    );
  `);
  pgm.sql(`CREATE INDEX organization_memberships_user_id_idx ON organization_memberships (user_id);`);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS organization_memberships;`);
  pgm.sql(`DROP TABLE IF EXISTS organizations;`);
  pgm.sql(`DROP TABLE IF EXISTS auth_identities;`);
  pgm.sql(`DROP TABLE IF EXISTS users;`);
};

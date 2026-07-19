/** V2-ARCHITECTURE.md §8.2, restricted to Phase 5's free-alpha grant source (ADR-0009: no Stripe yet). */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE entitlement_grants (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      source text NOT NULL CHECK (source IN ('trial', 'promo', 'support', 'admin', 'free_alpha')),
      feature_key text NOT NULL,
      limit_value jsonb,
      starts_at timestamptz NOT NULL DEFAULT now(),
      ends_at timestamptz,
      superseded_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now(),
      CHECK (ends_at IS NULL OR ends_at > starts_at)
    );
  `);
  pgm.sql(`CREATE INDEX entitlement_grants_organization_id_idx ON entitlement_grants (organization_id);`);
  pgm.sql(`
    CREATE INDEX entitlement_grants_active_idx ON entitlement_grants (organization_id, feature_key)
    WHERE superseded_at IS NULL;
  `);

  pgm.sql(`
    CREATE TABLE entitlement_projection (
      organization_id uuid PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
      features jsonb NOT NULL DEFAULT '{}'::jsonb,
      computed_at timestamptz NOT NULL DEFAULT now()
    );
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS entitlement_projection;`);
  pgm.sql(`DROP TABLE IF EXISTS entitlement_grants;`);
};

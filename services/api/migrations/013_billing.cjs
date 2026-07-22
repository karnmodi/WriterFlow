/** V2-ARCHITECTURE.md §8.2 — billing_customers, subscriptions, stripe_events. */

exports.shorthands = undefined;

const TENANT_BILLING_TABLES = ["billing_customers", "subscriptions"];

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE billing_customers (
      organization_id uuid PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
      stripe_customer_id text NOT NULL UNIQUE,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);

  pgm.sql(`
    CREATE TABLE subscriptions (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      stripe_subscription_id text NOT NULL UNIQUE,
      stripe_price_id text,
      status text NOT NULL,
      current_period_start timestamptz,
      current_period_end timestamptz,
      cancel_at_period_end boolean NOT NULL DEFAULT false,
      canceled_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX subscriptions_organization_id_idx ON subscriptions (organization_id);`);
  pgm.sql(`
    CREATE INDEX subscriptions_active_org_idx ON subscriptions (organization_id)
    WHERE status IN ('active', 'trialing', 'past_due');
  `);

  pgm.sql(`
    CREATE TABLE stripe_events (
      stripe_event_id text PRIMARY KEY,
      event_type text NOT NULL,
      payload jsonb NOT NULL,
      status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'processed', 'failed')),
      attempts integer NOT NULL DEFAULT 0,
      last_error text,
      received_at timestamptz NOT NULL DEFAULT now(),
      processed_at timestamptz
    );
  `);
  pgm.sql(`
    CREATE INDEX stripe_events_poll_idx ON stripe_events (received_at)
    WHERE status IN ('pending', 'failed');
  `);

  // Phase 7 grants subscription-sourced entitlements alongside the Phase 5 alpha source.
  pgm.sql(`ALTER TABLE entitlement_grants DROP CONSTRAINT IF EXISTS entitlement_grants_source_check;`);
  pgm.sql(`
    ALTER TABLE entitlement_grants ADD CONSTRAINT entitlement_grants_source_check
    CHECK (source IN ('trial', 'promo', 'support', 'admin', 'free_alpha', 'stripe'));
  `);

  for (const table of TENANT_BILLING_TABLES) {
    pgm.sql(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;`);
    pgm.sql(`ALTER TABLE ${table} FORCE ROW LEVEL SECURITY;`);
    pgm.sql(`
      CREATE POLICY ${table}_tenant_isolation ON ${table}
      FOR ALL
      USING (organization_id = current_tenant_id())
      WITH CHECK (organization_id = current_tenant_id());
    `);
    pgm.sql(`GRANT SELECT, INSERT, UPDATE, DELETE ON ${table} TO writerflow_app;`);
  }

  // Webhook inbox is global — events arrive before tenant context is known.
  pgm.sql(`GRANT SELECT, INSERT, UPDATE ON stripe_events TO writerflow_app;`);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS stripe_events;`);
  for (const table of [...TENANT_BILLING_TABLES].reverse()) {
    pgm.sql(`DROP POLICY IF EXISTS ${table}_tenant_isolation ON ${table};`);
    pgm.sql(`ALTER TABLE ${table} DISABLE ROW LEVEL SECURITY;`);
    pgm.sql(`DROP TABLE IF EXISTS ${table};`);
  }
  pgm.sql(`ALTER TABLE entitlement_grants DROP CONSTRAINT IF EXISTS entitlement_grants_source_check;`);
  pgm.sql(`
    ALTER TABLE entitlement_grants ADD CONSTRAINT entitlement_grants_source_check
    CHECK (source IN ('trial', 'promo', 'support', 'admin', 'free_alpha'));
  `);
};

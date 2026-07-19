/**
 * V2-ARCHITECTURE.md §8: FORCE ROW LEVEL SECURITY as defense in depth on
 * every tenant-owned table. `current_setting('app.tenant_id', true)` reads
 * the transaction-local value set by services/api/src/db.ts's
 * withTenantContext(); the `true` (missing_ok) makes it NULL rather than an
 * error when unset, so an unset tenant context fails closed (no rows match)
 * rather than open.
 *
 * writerflow_app is NOT the owner of these tables (migration 001 creates it
 * with no ownership) and RLS applies even to it via FORCE ROW LEVEL SECURITY
 * — only a table owner/superuser bypasses FORCE RLS, and writerflow_app is
 * neither.
 */

exports.shorthands = undefined;

const TENANT_ID_TABLES = [
  "organization_memberships",
  "devices",
  "privacy_preferences",
  "inference_requests",
  "quota_reservations",
  "usage_balances",
  "entitlement_grants",
  "entitlement_projection"
];

exports.up = (pgm) => {
  pgm.sql(`ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;`);
  pgm.sql(`ALTER TABLE organizations FORCE ROW LEVEL SECURITY;`);
  pgm.sql(`
    CREATE POLICY organizations_tenant_isolation ON organizations
    FOR ALL
    USING (id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (id = current_setting('app.tenant_id', true)::uuid);
  `);

  for (const table of TENANT_ID_TABLES) {
    pgm.sql(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;`);
    pgm.sql(`ALTER TABLE ${table} FORCE ROW LEVEL SECURITY;`);
    pgm.sql(`
      CREATE POLICY ${table}_tenant_isolation ON ${table}
      FOR ALL
      USING (organization_id = current_setting('app.tenant_id', true)::uuid)
      WITH CHECK (organization_id = current_setting('app.tenant_id', true)::uuid);
    `);
  }

  // usage_ledger's organization_id is nullable (post-anonymization rows, per
  // Docs/v2-data-retention-policy.md) — NULL never matches the tenant
  // predicate, so anonymized rows are invisible under RLS to every tenant
  // context, by construction, not by a special-cased clause.
  pgm.sql(`ALTER TABLE usage_ledger ENABLE ROW LEVEL SECURITY;`);
  pgm.sql(`ALTER TABLE usage_ledger FORCE ROW LEVEL SECURITY;`);
  // WITH CHECK here means the account-deletion anonymization UPDATE (nulling
  // organization_id/user_id, migration 005's trigger) can never succeed
  // through a normal tenant-scoped connection — by design. It must run as an
  // elevated internal role outside per-request RLS, since it deliberately
  // crosses the tenant boundary it's removing.
  pgm.sql(`
    CREATE POLICY usage_ledger_tenant_isolation ON usage_ledger
    FOR ALL
    USING (organization_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (organization_id = current_setting('app.tenant_id', true)::uuid);
  `);

  const allTenantTables = ["organizations", ...TENANT_ID_TABLES, "usage_ledger"];
  for (const table of allTenantTables) {
    pgm.sql(`GRANT SELECT, INSERT, UPDATE, DELETE ON ${table} TO writerflow_app;`);
  }
  pgm.sql(`GRANT SELECT ON pricing_versions TO writerflow_app;`);
  pgm.sql(`GRANT SELECT, INSERT ON users TO writerflow_app;`);
  pgm.sql(`GRANT UPDATE (status, updated_at) ON users TO writerflow_app;`);
  pgm.sql(`GRANT SELECT, INSERT, DELETE ON auth_identities TO writerflow_app;`);
  pgm.sql(`GRANT SELECT, INSERT, UPDATE ON outbox_events TO writerflow_app;`);
};

exports.down = (pgm) => {
  const allTenantTables = ["organizations", ...TENANT_ID_TABLES, "usage_ledger"];
  for (const table of allTenantTables) {
    pgm.sql(`DROP POLICY IF EXISTS ${table}_tenant_isolation ON ${table};`);
    pgm.sql(`ALTER TABLE ${table} DISABLE ROW LEVEL SECURITY;`);
  }
};

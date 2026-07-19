/**
 * Separate application and migration DB identities (V2-ARCHITECTURE.md §8,
 * Stage 5.1 "Use separate application and migration DB identities with least
 * privilege"). This migration runs as the migrator/owner role (the
 * superuser in local dev; a dedicated least-privilege migrator role in
 * staging/prod, provisioned by infra/bicep — never the app's own role).
 *
 * writerflow_app: the runtime role every services/api and services/worker
 * connection pool authenticates as. It owns nothing, has no BYPASSRLS, and
 * gets table-level grants (not ownership) from later migrations once each
 * table exists.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Staging/prod set WRITERFLOW_APP_ROLE_PASSWORD from Key Vault via the CI/CD
  // pipeline (infra/bicep) — never committed. The fallback below only ever
  // applies to a throwaway local Docker Postgres instance.
  pgm.sql(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'writerflow_app') THEN
        CREATE ROLE writerflow_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS PASSWORD '${process.env.WRITERFLOW_APP_ROLE_PASSWORD ?? "writerflow_app_dev_only"}';
      END IF;
    END
    $$;
  `);
  pgm.sql(`GRANT USAGE ON SCHEMA public TO writerflow_app;`);
  pgm.sql(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO writerflow_app;`);
};

exports.down = (pgm) => {
  // The ALTER DEFAULT PRIVILEGES entry from `up` is a schema-level ACL, not a
  // per-table grant — it survives every other migration's table drops and
  // must be revoked explicitly, or DROP ROLE fails with "privileges for
  // default privileges... still exist" (Postgres error 2BP01).
  pgm.sql(`ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM writerflow_app;`);
  pgm.sql(`REVOKE ALL PRIVILEGES ON SCHEMA public FROM writerflow_app;`);
  pgm.sql(`DROP ROLE IF EXISTS writerflow_app;`);
};

/**
 * Metadata-only reconciliation identity. It can cross tenant RLS only for
 * accounting/outbox tables and cannot read identity, device, privacy, or
 * billing data. Production supplies the password from Key Vault.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'writerflow_worker') THEN
        CREATE ROLE writerflow_worker LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS
          PASSWORD '${process.env.WRITERFLOW_WORKER_ROLE_PASSWORD ?? "writerflow_worker_dev_only"}';
      END IF;
    END
    $$;
  `);
  pgm.sql(`GRANT USAGE ON SCHEMA public TO writerflow_worker;`);
  pgm.sql(`GRANT SELECT, UPDATE ON inference_requests, quota_reservations, usage_balances TO writerflow_worker;`);
  pgm.sql(`GRANT SELECT ON usage_ledger TO writerflow_worker;`);
  pgm.sql(`GRANT SELECT, UPDATE ON outbox_events TO writerflow_worker;`);
};

exports.down = (pgm) => {
  pgm.sql(`REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM writerflow_worker;`);
  pgm.sql(`REVOKE ALL PRIVILEGES ON SCHEMA public FROM writerflow_worker;`);
  pgm.sql(`DROP ROLE IF EXISTS writerflow_worker;`);
};

/**
 * Fixes a real bootstrap problem migration 008 left unaddressed: `devices`
 * has FORCE ROW LEVEL SECURITY keyed on organization_id (migration 008), but
 * POST /v2/device/token and POST /v2/token/refresh must look up a device by
 * its bare ID *before* any tenant context can be set — that's exactly what
 * they're trying to resolve. Without this, those queries would silently
 * return zero rows under writerflow_app in a real deployment (RLS fails
 * closed), even though everything passed locally against a role that never
 * hit this path in Stage 5.1's tests.
 *
 * Fix: an additional PERMISSIVE policy, OR'd with the existing tenant policy
 * (Postgres combines multiple permissive policies for the same table with
 * OR), that grants full row access only while a session-local flag is set.
 * That flag is never derived from client input — only services/api/src/db.ts's
 * withDeviceBootstrapLookup() sets it, transaction-locally (SET LOCAL, same
 * pattern as withTenantContext's app.tenant_id), for exactly the pairing/
 * refresh code paths in services/api/src/pairing/service.ts. No role gets
 * BYPASSRLS — the phase-wide non-negotiable stays true; this is a narrow,
 * auditable, code-reviewed escape hatch, not a privilege grant.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE POLICY devices_bootstrap_lookup ON devices
    FOR ALL
    USING (current_setting('app.allow_device_bootstrap_lookup', true) = 'true')
    WITH CHECK (current_setting('app.allow_device_bootstrap_lookup', true) = 'true');
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP POLICY IF EXISTS devices_bootstrap_lookup ON devices;`);
};

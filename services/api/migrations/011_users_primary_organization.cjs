/**
 * Stage 5.2 /device/approve needs to resolve "does this Entra identity
 * already have an account, and if so which organization" idempotently.
 * `auth_identities` (unprotected, looked up by (issuer, subject)) gives the
 * user_id directly, but the user's personal organization_id lives on
 * `organizations`/`organization_memberships`, both RLS-protected by
 * organization_id — the exact value we're trying to discover. Rather than
 * add another bootstrap-lookup RLS policy (migration 010's pattern) for
 * every table this touches, denormalize the one non-sensitive pointer onto
 * `users` (itself unprotected), which is enough to establish tenant context
 * once and then read everything else through the normal tenant policy.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`ALTER TABLE users ADD COLUMN primary_organization_id uuid REFERENCES organizations(id);`);
};

exports.down = (pgm) => {
  pgm.sql(`ALTER TABLE users DROP COLUMN primary_organization_id;`);
};

/**
 * Stage 5.4 "Minimum accounting prerequisite": usage_ledger.pricing_version_id
 * is NOT NULL, so at least one pricing_versions row must exist before any
 * inference request can be committed. This seeds a flat, non-token-based
 * placeholder — 1 billable unit per completed request, no per-token
 * conversion — matching the vertical slice's DevEchoProvider stand-in
 * (services/api/src/inference/devEchoProvider.ts). Stage 5.5's "Logical
 * route configuration" replaces this with real per-route/per-token pricing
 * once a real Azure OpenAI provider exists.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO pricing_versions (version_label, effective_at, conversion)
    VALUES (
      'alpha-flat-v1',
      now(),
      '{"description": "Stage 5.4 vertical-slice placeholder: flat billable units per completed request, no token-based conversion yet.", "flatUnitsPerRequest": 1}'::jsonb
    )
    ON CONFLICT (version_label) DO NOTHING;
  `);
};

exports.down = (pgm) => {
  // pricing_versions is append-only by trigger (migration 005) — deliberately
  // bypassed here since a migration `down` is an administrative rollback of
  // this migration's own seed data, not application usage.
  pgm.sql(`ALTER TABLE pricing_versions DISABLE TRIGGER pricing_versions_forbid_delete;`);
  pgm.sql(`DELETE FROM pricing_versions WHERE version_label = 'alpha-flat-v1';`);
  pgm.sql(`ALTER TABLE pricing_versions ENABLE TRIGGER pricing_versions_forbid_delete;`);
};

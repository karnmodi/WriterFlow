/**
 * V2-ARCHITECTURE.md §8.3 + §9.2 + Docs/v2-data-retention-policy.md. Both
 * tables are append-only by construction: a DB-level trigger, not just
 * application discipline, blocks DELETE and blocks UPDATE of any financial
 * field. usage_ledger's trigger carves out exactly one exception — nulling
 * user_id/organization_id — for the account-deletion anonymization path in
 * Docs/v2-data-retention-policy.md (the row survives 7 years for
 * reconciliation; only tenant linkage is removed).
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE pricing_versions (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      version_label text NOT NULL UNIQUE,
      effective_at timestamptz NOT NULL,
      conversion jsonb NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is append-only: % is not permitted', TG_TABLE_NAME, TG_OP;
    END;
    $$ LANGUAGE plpgsql;
  `);
  pgm.sql(`
    CREATE TRIGGER pricing_versions_forbid_update
    BEFORE UPDATE ON pricing_versions
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
  `);
  pgm.sql(`
    CREATE TRIGGER pricing_versions_forbid_delete
    BEFORE DELETE ON pricing_versions
    FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
  `);

  pgm.sql(`
    CREATE TABLE usage_ledger (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      inference_request_id uuid REFERENCES inference_requests(id) ON DELETE SET NULL,
      organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
      user_id uuid REFERENCES users(id) ON DELETE SET NULL,
      stage text NOT NULL CHECK (stage IN ('classifier', 'enhancer', 'generator')),
      route text NOT NULL,
      provider_target_id text,
      pricing_version_id uuid NOT NULL REFERENCES pricing_versions(id),
      input_tokens integer,
      output_tokens integer,
      cached_tokens integer,
      reasoning_tokens integer,
      provider_cost_micros bigint NOT NULL DEFAULT 0 CHECK (provider_cost_micros >= 0),
      billable_units integer NOT NULL DEFAULT 0 CHECK (billable_units >= 0),
      status text NOT NULL CHECK (status IN ('committed', 'reversed')),
      reversal_of_id uuid REFERENCES usage_ledger(id),
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  pgm.sql(`CREATE INDEX usage_ledger_organization_id_idx ON usage_ledger (organization_id);`);
  pgm.sql(`CREATE INDEX usage_ledger_user_id_idx ON usage_ledger (user_id);`);
  pgm.sql(`CREATE INDEX usage_ledger_inference_request_id_idx ON usage_ledger (inference_request_id);`);
  pgm.sql(`
    CREATE UNIQUE INDEX usage_ledger_one_committed_stage_per_request
    ON usage_ledger (inference_request_id, stage)
    WHERE status = 'committed' AND inference_request_id IS NOT NULL;
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION usage_ledger_forbid_delete() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'usage_ledger is append-only: DELETE is not permitted; insert a reversing entry instead';
    END;
    $$ LANGUAGE plpgsql;
  `);
  pgm.sql(`
    CREATE TRIGGER usage_ledger_forbid_delete
    BEFORE DELETE ON usage_ledger
    FOR EACH ROW EXECUTE FUNCTION usage_ledger_forbid_delete();
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION usage_ledger_restrict_update() RETURNS trigger AS $$
    BEGIN
      IF NEW.id IS DISTINCT FROM OLD.id
        OR NEW.inference_request_id IS DISTINCT FROM OLD.inference_request_id
        OR NEW.stage IS DISTINCT FROM OLD.stage
        OR NEW.route IS DISTINCT FROM OLD.route
        OR NEW.provider_target_id IS DISTINCT FROM OLD.provider_target_id
        OR NEW.pricing_version_id IS DISTINCT FROM OLD.pricing_version_id
        OR NEW.input_tokens IS DISTINCT FROM OLD.input_tokens
        OR NEW.output_tokens IS DISTINCT FROM OLD.output_tokens
        OR NEW.cached_tokens IS DISTINCT FROM OLD.cached_tokens
        OR NEW.reasoning_tokens IS DISTINCT FROM OLD.reasoning_tokens
        OR NEW.provider_cost_micros IS DISTINCT FROM OLD.provider_cost_micros
        OR NEW.billable_units IS DISTINCT FROM OLD.billable_units
        OR NEW.status IS DISTINCT FROM OLD.status
        OR NEW.reversal_of_id IS DISTINCT FROM OLD.reversal_of_id
        OR NEW.created_at IS DISTINCT FROM OLD.created_at
      THEN
        RAISE EXCEPTION 'usage_ledger is append-only: only user_id/organization_id may change (account-deletion anonymization), and only to NULL';
      END IF;
      IF NEW.user_id IS NOT NULL OR NEW.organization_id IS NOT NULL THEN
        RAISE EXCEPTION 'usage_ledger anonymization must set user_id and organization_id to NULL, not another value';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
  `);
  pgm.sql(`
    CREATE TRIGGER usage_ledger_restrict_update
    BEFORE UPDATE ON usage_ledger
    FOR EACH ROW EXECUTE FUNCTION usage_ledger_restrict_update();
  `);

  pgm.sql(`
    CREATE TABLE usage_balances (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      period_start date NOT NULL,
      period_end date NOT NULL,
      used_units integer NOT NULL DEFAULT 0 CHECK (used_units >= 0),
      allowance_units integer NOT NULL DEFAULT 0 CHECK (allowance_units >= 0),
      updated_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (organization_id, period_start)
    );
  `);
  pgm.sql(`
    CREATE TRIGGER usage_balances_set_updated_at
    BEFORE UPDATE ON usage_balances
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP TABLE IF EXISTS usage_balances;`);
  pgm.sql(`DROP TABLE IF EXISTS usage_ledger;`);
  pgm.sql(`DROP FUNCTION IF EXISTS usage_ledger_restrict_update();`);
  pgm.sql(`DROP FUNCTION IF EXISTS usage_ledger_forbid_delete();`);
  pgm.sql(`DROP TABLE IF EXISTS pricing_versions;`);
  pgm.sql(`DROP FUNCTION IF EXISTS forbid_mutation();`);
};

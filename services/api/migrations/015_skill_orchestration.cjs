/**
 * Phase 6 skill orchestration metadata. Raw draft, conversation, adjustment,
 * specialist input, and output are deliberately absent from every table.
 */
exports.up = (pgm) => {
  pgm.dropConstraint("inference_requests", "inference_requests_mode_check");
  pgm.addConstraint("inference_requests", "inference_requests_mode_check", {
    check: "mode IN ('explicit', 'auto', 'adjust')"
  });
  pgm.addColumns("inference_requests", {
    skill_id: { type: "text" },
    skill_version: { type: "text" },
    decision_source: { type: "text" },
    decision_confidence: { type: "numeric(5,4)" },
    execution_mode: { type: "text" },
    shadow_skill_id: { type: "text" },
    shadow_skill_version: { type: "text" },
    shadow_decision_confidence: { type: "numeric(5,4)" },
    shadow_reason_code: { type: "text" },
    adjustment_of: { type: "uuid", references: "inference_requests(id)" }
  });
  pgm.addConstraint("inference_requests", "inference_requests_decision_source_check", {
    check: "decision_source IS NULL OR decision_source IN ('explicit', 'rule', 'classifier', 'fallback', 'adjustment')"
  });
  pgm.addConstraint("inference_requests", "inference_requests_execution_mode_check", {
    check: "execution_mode IS NULL OR execution_mode IN ('direct', 'composed')"
  });
  pgm.addConstraint("inference_requests", "inference_requests_confidence_check", {
    check: "decision_confidence IS NULL OR (decision_confidence >= 0 AND decision_confidence <= 1)"
  });
  pgm.addConstraint("inference_requests", "inference_requests_shadow_confidence_check", {
    check: "shadow_decision_confidence IS NULL OR (shadow_decision_confidence >= 0 AND shadow_decision_confidence <= 1)"
  });
  const skillIds = "'reply','continue','improve','correct','shorten','expand','tone_adapt','prompt_enhance','custom_adjust'";
  pgm.addConstraint("inference_requests", "inference_requests_skill_id_check", {
    check: `skill_id IS NULL OR skill_id IN (${skillIds})`
  });
  pgm.addConstraint("inference_requests", "inference_requests_shadow_skill_id_check", {
    check: `shadow_skill_id IS NULL OR shadow_skill_id IN (${skillIds})`
  });

  pgm.addColumns("usage_ledger", {
    stage_key: { type: "text", notNull: true, default: "generator" },
    attempt_no: { type: "integer", notNull: true, default: 1 }
  });
  pgm.addConstraint("usage_ledger", "usage_ledger_attempt_no_check", { check: "attempt_no >= 1" });
  pgm.dropIndex("usage_ledger", ["inference_request_id", "stage"], {
    name: "usage_ledger_one_committed_stage_per_request"
  });
  pgm.createIndex("usage_ledger", ["inference_request_id", "stage_key", "attempt_no"], {
    name: "usage_ledger_one_attempt_per_stage_key",
    unique: true
  });
  pgm.sql(`
    CREATE OR REPLACE FUNCTION usage_ledger_restrict_update() RETURNS trigger AS $$
    BEGIN
      IF NEW.id IS DISTINCT FROM OLD.id
        OR NEW.inference_request_id IS DISTINCT FROM OLD.inference_request_id
        OR NEW.stage IS DISTINCT FROM OLD.stage
        OR NEW.stage_key IS DISTINCT FROM OLD.stage_key
        OR NEW.attempt_no IS DISTINCT FROM OLD.attempt_no
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
        RAISE EXCEPTION 'usage_ledger is append-only: only user_id/organization_id may change, and only to NULL';
      END IF;
      IF NEW.user_id IS NOT NULL OR NEW.organization_id IS NOT NULL THEN
        RAISE EXCEPTION 'usage_ledger anonymization must set user_id and organization_id to NULL';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
  `);

  pgm.createTable("classifier_feedback", {
    id: { type: "uuid", primaryKey: true, default: pgm.func("gen_random_uuid()") },
    organization_id: { type: "uuid", notNull: true, references: "organizations(id)", onDelete: "CASCADE" },
    user_id: { type: "uuid", references: "users(id)", onDelete: "SET NULL" },
    inference_request_id: { type: "uuid", notNull: true, references: "inference_requests(id)", onDelete: "CASCADE" },
    original_skill_id: { type: "text", notNull: true },
    revised_skill_id: { type: "text" },
    app_category: { type: "text" },
    confidence_band: { type: "text", notNull: true },
    outcome: { type: "text", notNull: true },
    created_at: { type: "timestamptz", notNull: true, default: pgm.func("now()") }
  });
  pgm.addConstraint("classifier_feedback", "classifier_feedback_outcome_check", {
    check: "outcome IN ('accepted', 'adjusted', 'discarded')"
  });
  pgm.addConstraint("classifier_feedback", "classifier_feedback_confidence_band_check", {
    check: "confidence_band IN ('low', 'medium', 'high')"
  });
  pgm.addConstraint("classifier_feedback", "classifier_feedback_skill_id_check", {
    check: `original_skill_id IN (${skillIds}) AND (revised_skill_id IS NULL OR revised_skill_id IN (${skillIds}))`
  });
  pgm.addConstraint("classifier_feedback", "classifier_feedback_app_category_check", {
    check: "app_category IS NULL OR app_category IN ('email','personal_message','work_message','llm_chat','code','other')"
  });
  pgm.createIndex("classifier_feedback", ["organization_id", "created_at"]);
  pgm.createIndex("classifier_feedback", ["inference_request_id", "outcome"], {
    name: "classifier_feedback_one_outcome_per_request",
    unique: true
  });
  pgm.sql(`ALTER TABLE classifier_feedback ENABLE ROW LEVEL SECURITY;`);
  pgm.sql(`ALTER TABLE classifier_feedback FORCE ROW LEVEL SECURITY;`);
  pgm.sql(`
    CREATE POLICY classifier_feedback_tenant_isolation ON classifier_feedback
    USING (organization_id = current_tenant_id())
    WITH CHECK (organization_id = current_tenant_id());
  `);
  pgm.sql(`GRANT SELECT, INSERT ON classifier_feedback TO writerflow_app;`);
  pgm.sql(`GRANT SELECT ON classifier_feedback TO writerflow_worker;`);
};

exports.down = (pgm) => {
  pgm.dropTable("classifier_feedback");
  pgm.dropIndex("usage_ledger", ["inference_request_id", "stage_key", "attempt_no"], {
    name: "usage_ledger_one_attempt_per_stage_key"
  });
  pgm.dropConstraint("usage_ledger", "usage_ledger_attempt_no_check");
  pgm.dropColumns("usage_ledger", ["stage_key", "attempt_no"]);
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
        RAISE EXCEPTION 'usage_ledger is append-only: only user_id/organization_id may change, and only to NULL';
      END IF;
      IF NEW.user_id IS NOT NULL OR NEW.organization_id IS NOT NULL THEN
        RAISE EXCEPTION 'usage_ledger anonymization must set user_id and organization_id to NULL';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
  `);
  pgm.createIndex("usage_ledger", ["inference_request_id", "stage"], {
    name: "usage_ledger_one_committed_stage_per_request",
    unique: true,
    where: "status = 'committed'"
  });
  pgm.dropConstraint("inference_requests", "inference_requests_confidence_check");
  pgm.dropConstraint("inference_requests", "inference_requests_shadow_confidence_check");
  pgm.dropConstraint("inference_requests", "inference_requests_shadow_skill_id_check");
  pgm.dropConstraint("inference_requests", "inference_requests_skill_id_check");
  pgm.dropConstraint("inference_requests", "inference_requests_execution_mode_check");
  pgm.dropConstraint("inference_requests", "inference_requests_decision_source_check");
  pgm.dropColumns("inference_requests", [
    "skill_id", "skill_version", "decision_source", "decision_confidence", "execution_mode",
    "shadow_skill_id", "shadow_skill_version", "shadow_decision_confidence", "shadow_reason_code", "adjustment_of"
  ]);
  pgm.dropConstraint("inference_requests", "inference_requests_mode_check");
  pgm.addConstraint("inference_requests", "inference_requests_mode_check", {
    check: "mode IN ('explicit', 'auto')"
  });
};

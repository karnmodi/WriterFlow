import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { ClassifierFeedbackRequestSchema } from "@writerflow/shared";
import { requireDeviceAuth } from "../auth/guard.js";
import { withTenantContext } from "../db.js";
import { ApiError, sendError } from "../errors.js";
import type { SigningKeyProvider } from "../jwt/keys.js";

function confidenceBand(value: number | null): "low" | "medium" | "high" {
  if (value == null || value < 0.65) return "low";
  return value < 0.85 ? "medium" : "high";
}

/** Content-free classifier outcome capture. Original skill/confidence are
 * resolved from the authenticated inference row, never trusted from the Mac. */
export function registerInferenceFeedbackRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider
): void {
  app.post("/inference/feedback", async (request, reply) => {
    const ctx = await requireDeviceAuth(request, pool, keys);
    const parsed = ClassifierFeedbackRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Feedback body failed schema validation."));
      return;
    }

    const saved = await withTenantContext(pool, ctx.organizationId, async (client) => {
      const inference = await client.query<{
        id: string;
        skill_id: string | null;
        decision_confidence: string | null;
      }>(
        `SELECT id, skill_id, decision_confidence
         FROM inference_requests
         WHERE organization_id = $1 AND user_id = $2 AND operation_id = $3`,
        [ctx.organizationId, ctx.userId, parsed.data.operationId]
      );
      const row = inference.rows[0];
      if (!row?.skill_id) return false;
      await client.query(
        `INSERT INTO classifier_feedback
          (organization_id, user_id, inference_request_id, original_skill_id, revised_skill_id,
           app_category, confidence_band, outcome)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (inference_request_id, outcome) DO NOTHING`,
        [
          ctx.organizationId,
          ctx.userId,
          row.id,
          row.skill_id,
          parsed.data.revisedSkillId ?? null,
          parsed.data.appCategory ?? null,
          confidenceBand(row.decision_confidence == null ? null : Number(row.decision_confidence)),
          parsed.data.outcome
        ]
      );
      return true;
    });
    if (!saved) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 404, "Inference operation was not found."));
      return;
    }
    reply.code(204).send();
  });
}

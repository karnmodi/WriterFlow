import type pg from "pg";
import { FREE_ALPHA_MONTHLY_UNITS } from "../pairing/snapshot.js";

/** V2-ARCHITECTURE.md §9.3 — feature keys independent of model slugs. */
export const FEATURE_KEYS = [
  "auto_write",
  "standard_route",
  "premium_route",
  "prompt_enhancer",
  "personalization_sync",
  "context_chars_limit",
  "monthly_units",
  "concurrent_requests",
  "priority_service"
] as const;

export type FeatureKey = (typeof FEATURE_KEYS)[number];
export type Plan = "free" | "pro";

export const FREE_PLAN_FEATURES = ["auto_write", "standard_route"] as const;
export const PRO_PLAN_FEATURES = [
  "auto_write",
  "standard_route",
  "premium_route",
  "prompt_enhancer",
  "priority_service"
] as const;

const PRO_ACCESS_STATUSES = new Set(["active", "trialing"]);
const GRACE_STATUSES = new Set(["past_due"]);

export const DEFAULT_CONTEXT_CHARS_LIMIT = 24_000;
export const DEFAULT_CONCURRENT_REQUESTS = 1;
export const PRO_CONCURRENT_REQUESTS = 3;

export interface ProjectionFeatures {
  monthly_units_included?: number;
  context_chars_limit?: number;
  concurrent_requests?: number;
}

export interface SubscriptionSnapshot {
  status: string;
  currentPeriodEnd: Date | null;
  cancelAtPeriodEnd: boolean;
}

export interface EvaluatedEntitlement {
  plan: Plan;
  monthlyUnitsIncluded: number;
  features: string[];
  contextCharsLimit: number;
  concurrentRequests: number;
  inGracePeriod: boolean;
  subscriptionStatus: string | null;
}

function hasProAccess(subscription: SubscriptionSnapshot | null, now: Date): boolean {
  if (!subscription) return false;
  if (PRO_ACCESS_STATUSES.has(subscription.status)) return true;
  if (GRACE_STATUSES.has(subscription.status)) {
    return subscription.currentPeriodEnd == null || subscription.currentPeriodEnd.getTime() >= now.getTime();
  }
  return false;
}

/**
 * Pure evaluation of plan/features from the fast entitlement_projection row plus
 * normalized subscription state. No Stripe calls — authorization reads Postgres only.
 */
export function evaluateEntitlement(
  projection: ProjectionFeatures,
  subscription: SubscriptionSnapshot | null,
  now = new Date()
): EvaluatedEntitlement {
  const monthlyUnitsIncluded = projection.monthly_units_included ?? FREE_ALPHA_MONTHLY_UNITS;
  const contextCharsLimit = projection.context_chars_limit ?? DEFAULT_CONTEXT_CHARS_LIMIT;
  const proAccess = hasProAccess(subscription, now);
  const inGracePeriod = subscription != null && GRACE_STATUSES.has(subscription.status) && proAccess;

  if (proAccess) {
    return {
      plan: "pro",
      monthlyUnitsIncluded,
      features: [...PRO_PLAN_FEATURES],
      contextCharsLimit,
      concurrentRequests: projection.concurrent_requests ?? PRO_CONCURRENT_REQUESTS,
      inGracePeriod,
      subscriptionStatus: subscription?.status ?? null
    };
  }

  return {
    plan: "free",
    monthlyUnitsIncluded,
    features: [...FREE_PLAN_FEATURES],
    contextCharsLimit,
    concurrentRequests: projection.concurrent_requests ?? DEFAULT_CONCURRENT_REQUESTS,
    inGracePeriod: false,
    subscriptionStatus: subscription?.status ?? null
  };
}

export async function readEvaluatedEntitlement(
  client: pg.PoolClient,
  organizationId: string,
  now = new Date()
): Promise<EvaluatedEntitlement> {
  const projectionResult = await client.query<{ features: ProjectionFeatures }>(
    `SELECT features FROM entitlement_projection WHERE organization_id = $1`,
    [organizationId]
  );
  const subscriptionResult = await client.query<{
    status: string;
    current_period_end: Date | null;
    cancel_at_period_end: boolean;
  }>(
    `SELECT status, current_period_end, cancel_at_period_end
     FROM subscriptions
     WHERE organization_id = $1
     ORDER BY
       CASE status
         WHEN 'active' THEN 1
         WHEN 'trialing' THEN 2
         WHEN 'past_due' THEN 3
         ELSE 4
       END,
       updated_at DESC
     LIMIT 1`,
    [organizationId]
  );

  const subscriptionRow = subscriptionResult.rows[0];
  const subscription = subscriptionRow
    ? {
        status: subscriptionRow.status,
        currentPeriodEnd: subscriptionRow.current_period_end,
        cancelAtPeriodEnd: subscriptionRow.cancel_at_period_end
      }
    : null;

  return evaluateEntitlement(projectionResult.rows[0]?.features ?? {}, subscription, now);
}

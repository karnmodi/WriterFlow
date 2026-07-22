import { describe, expect, it } from "vitest";
import { FREE_ALPHA_MONTHLY_UNITS } from "../src/pairing/snapshot.js";
import {
  DEFAULT_CONCURRENT_REQUESTS,
  DEFAULT_CONTEXT_CHARS_LIMIT,
  PRO_CONCURRENT_REQUESTS,
  evaluateEntitlement,
  FREE_PLAN_FEATURES,
  PRO_PLAN_FEATURES
} from "../src/entitlements/engine.js";

describe("evaluateEntitlement", () => {
  it("returns free plan defaults from projection when no subscription exists", () => {
    const result = evaluateEntitlement({ monthly_units_included: 500 }, null);
    expect(result.plan).toBe("free");
    expect(result.monthlyUnitsIncluded).toBe(500);
    expect(result.features).toEqual([...FREE_PLAN_FEATURES]);
    expect(result.contextCharsLimit).toBe(DEFAULT_CONTEXT_CHARS_LIMIT);
    expect(result.concurrentRequests).toBe(DEFAULT_CONCURRENT_REQUESTS);
    expect(result.inGracePeriod).toBe(false);
    expect(result.subscriptionStatus).toBeNull();
  });

  it("falls back to free-alpha units when projection omits monthly_units_included", () => {
    const result = evaluateEntitlement({}, null);
    expect(result.monthlyUnitsIncluded).toBe(FREE_ALPHA_MONTHLY_UNITS);
  });

  it("returns pro features for an active subscription", () => {
    const result = evaluateEntitlement(
      { monthly_units_included: 5000, context_chars_limit: 48_000 },
      { status: "active", currentPeriodEnd: new Date("2026-08-01T00:00:00.000Z"), cancelAtPeriodEnd: false }
    );
    expect(result.plan).toBe("pro");
    expect(result.monthlyUnitsIncluded).toBe(5000);
    expect(result.features).toEqual([...PRO_PLAN_FEATURES]);
    expect(result.contextCharsLimit).toBe(48_000);
    expect(result.concurrentRequests).toBe(PRO_CONCURRENT_REQUESTS);
    expect(result.inGracePeriod).toBe(false);
    expect(result.subscriptionStatus).toBe("active");
  });

  it("keeps pro access during past_due grace while the current period has not ended", () => {
    const now = new Date("2026-07-15T00:00:00.000Z");
    const result = evaluateEntitlement(
      {},
      { status: "past_due", currentPeriodEnd: new Date("2026-07-31T00:00:00.000Z"), cancelAtPeriodEnd: false },
      now
    );
    expect(result.plan).toBe("pro");
    expect(result.inGracePeriod).toBe(true);
  });

  it("downgrades to free when past_due grace has expired", () => {
    const now = new Date("2026-08-01T00:00:00.000Z");
    const result = evaluateEntitlement(
      {},
      { status: "past_due", currentPeriodEnd: new Date("2026-07-31T00:00:00.000Z"), cancelAtPeriodEnd: false },
      now
    );
    expect(result.plan).toBe("free");
    expect(result.inGracePeriod).toBe(false);
  });

  it("downgrades canceled subscriptions to free", () => {
    const result = evaluateEntitlement(
      {},
      { status: "canceled", currentPeriodEnd: new Date("2026-07-31T00:00:00.000Z"), cancelAtPeriodEnd: true }
    );
    expect(result.plan).toBe("free");
    expect(result.features).toEqual([...FREE_PLAN_FEATURES]);
  });
});

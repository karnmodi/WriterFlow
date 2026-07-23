export type BillingCadence = "monthly" | "annual" | null;

export type MembershipFeatureFlag =
  | "auto_write"
  | "standard_route"
  | "premium_route"
  | "prompt_enhancer"
  | "personalization_sync"
  | "longer_context"
  | "priority_service";

export interface MembershipPlan {
  id: "free" | "pro";
  tierName: string;
  unitAllowance: number | null;
  priceCents: number | null;
  currency: "GBP";
  billingCadence: BillingCadence;
  featureFlags: MembershipFeatureFlag[];
  trialAvailable: boolean;
  availability: "available" | "in-development";
}

export const membershipPlans: MembershipPlan[] = [
  {
    id: "free",
    tierName: "Free",
    unitAllowance: 500,
    priceCents: 0,
    currency: "GBP",
    billingCadence: null,
    featureFlags: ["auto_write", "standard_route", "prompt_enhancer"],
    trialAvailable: false,
    availability: "available",
  },
  {
    id: "pro",
    tierName: "Pro",
    unitAllowance: null,
    priceCents: null,
    currency: "GBP",
    billingCadence: "monthly",
    featureFlags: [
      "auto_write",
      "standard_route",
      "premium_route",
      "prompt_enhancer",
      "personalization_sync",
      "longer_context",
      "priority_service",
    ],
    trialAvailable: false,
    availability: "in-development",
  },
];

export const membershipFeatureLabels: Record<MembershipFeatureFlag, string> = {
  auto_write: "Writing assistance wherever you type",
  standard_route: "Standard rewrite route",
  premium_route: "Premium route access",
  prompt_enhancer: "Prompt enhancement",
  personalization_sync: "Advanced personalization",
  longer_context: "Longer context support",
  priority_service: "Priority processing when available",
};

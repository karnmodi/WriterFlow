import Stripe from "stripe";
import type { AppConfig } from "../config.js";

export interface StripeServices {
  client: Stripe | null;
  webhookSecret: string | null;
}

export function isStripeBillingConfigured(config: Pick<AppConfig, "STRIPE_SECRET_KEY">): boolean {
  return Boolean(config.STRIPE_SECRET_KEY);
}

export function isStripeWebhookConfigured(config: Pick<AppConfig, "STRIPE_WEBHOOK_SECRET">): boolean {
  return Boolean(config.STRIPE_WEBHOOK_SECRET);
}

/** Backend-only Stripe SDK wrapper. Returns null client when STRIPE_SECRET_KEY is unset. */
export function createStripeServices(config: Pick<AppConfig, "STRIPE_SECRET_KEY" | "STRIPE_WEBHOOK_SECRET">): StripeServices {
  const client = config.STRIPE_SECRET_KEY
    ? new Stripe(config.STRIPE_SECRET_KEY, { typescript: true })
    : null;

  return {
    client,
    webhookSecret: config.STRIPE_WEBHOOK_SECRET ?? null
  };
}

export function verifyStripeWebhookEvent(
  services: StripeServices,
  rawBody: Buffer,
  signatureHeader: string | undefined
): Stripe.Event {
  if (!services.webhookSecret) {
    throw new StripeWebhookConfigError("Stripe webhook verification is not configured.");
  }
  if (!signatureHeader) {
    throw new StripeWebhookVerificationError("Missing Stripe-Signature header.");
  }

  return Stripe.webhooks.constructEvent(rawBody, signatureHeader, services.webhookSecret);
}

export class StripeWebhookConfigError extends Error {
  override readonly name = "StripeWebhookConfigError";
}

export class StripeWebhookVerificationError extends Error {
  override readonly name = "StripeWebhookVerificationError";
}

import { describe, expect, it } from "vitest";
import Stripe from "stripe";
import {
  createStripeServices,
  isStripeBillingConfigured,
  isStripeWebhookConfigured,
  verifyStripeWebhookEvent
} from "../src/billing/stripe.js";
import { fakeConfig } from "./helpers/fakeConfig.js";

describe("createStripeServices", () => {
  it("returns null client when STRIPE_SECRET_KEY is unset", () => {
    const services = createStripeServices(fakeConfig());
    expect(services.client).toBeNull();
    expect(services.webhookSecret).toBeNull();
    expect(isStripeBillingConfigured(fakeConfig())).toBe(false);
    expect(isStripeWebhookConfigured(fakeConfig())).toBe(false);
  });

  it("returns a client and webhook secret when configured", () => {
    const config = fakeConfig({
      STRIPE_SECRET_KEY: "sk_test_example",
      STRIPE_WEBHOOK_SECRET: "whsec_test_example"
    });
    const services = createStripeServices(config);
    expect(services.client).toBeInstanceOf(Stripe);
    expect(services.webhookSecret).toBe("whsec_test_example");
    expect(isStripeBillingConfigured(config)).toBe(true);
    expect(isStripeWebhookConfigured(config)).toBe(true);
  });
});

describe("verifyStripeWebhookEvent", () => {
  it("verifies a signed test payload", () => {
    const secret = "whsec_test_secret";
    const payload = JSON.stringify({
      id: "evt_test_webhook",
      object: "event",
      type: "customer.subscription.updated",
      data: { object: { id: "sub_test" } }
    });
    const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret });
    const services = createStripeServices(fakeConfig({ STRIPE_WEBHOOK_SECRET: secret }));

    const event = verifyStripeWebhookEvent(services, Buffer.from(payload), signature);
    expect(event.id).toBe("evt_test_webhook");
    expect(event.type).toBe("customer.subscription.updated");
  });
});

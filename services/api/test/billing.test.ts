import { describe, expect, it, vi } from "vitest";
import Stripe from "stripe";
import { buildApp } from "../src/app.js";
import { LocalDevSigningKeyProvider } from "../src/jwt/keys.js";
import { mintAccessToken } from "../src/jwt/issuer.js";
import { fakeConfig } from "./helpers/fakeConfig.js";

function createAuthedPool() {
  const client = {
    query: vi.fn(async (sql: string) => {
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") {
        return { rows: [] };
      }
      if (sql.startsWith("SELECT set_config")) {
        return { rows: [] };
      }
      if (sql.includes("revoked_at")) {
        return { rows: [{ revoked_at: null }] };
      }
      if (sql.includes("FROM users")) {
        return { rows: [{ status: "active" }] };
      }
      if (sql.includes("INSERT INTO stripe_events")) {
        return { rowCount: 1, rows: [{ stripe_event_id: "evt_test_webhook" }] };
      }
      return { rows: [] };
    }),
    release: vi.fn()
  };

  return {
    connect: vi.fn().mockResolvedValue(client),
    query: vi.fn()
  };
}

describe("billing routes", () => {
  it("POST /billing/checkout-session returns 501 when Stripe is not configured", async () => {
    const pool = createAuthedPool();
    const keys = new LocalDevSigningKeyProvider();
    const app = buildApp({ config: fakeConfig(), pool: pool as never, signingKeys: keys, entraVerifier: null });
    const { token } = await mintAccessToken(keys, {
      userId: "user-1",
      deviceId: "device-1",
      organizationId: "org-1",
      scope: "inference"
    });

    const response = await app.inject({
      method: "POST",
      url: "/billing/checkout-session",
      headers: { authorization: `Bearer ${token}` },
      payload: { priceLookupKey: "pro_monthly" }
    });

    expect(response.statusCode).toBe(501);
    expect(response.json()).toMatchObject({ code: "INTERNAL_ERROR" });
    await app.close();
  });

  it("POST /billing/checkout-session returns 401 without a bearer token", async () => {
    const pool = createAuthedPool();
    const app = buildApp({
      config: fakeConfig({ STRIPE_SECRET_KEY: "sk_test_example" }),
      pool: pool as never,
      signingKeys: new LocalDevSigningKeyProvider(),
      entraVerifier: null
    });

    const response = await app.inject({
      method: "POST",
      url: "/billing/checkout-session",
      payload: { priceLookupKey: "pro_monthly" }
    });

    expect(response.statusCode).toBe(401);
    await app.close();
  });

  it("POST /webhooks/stripe returns 503 when webhook secret is not configured", async () => {
    const pool = createAuthedPool();
    const app = buildApp({ config: fakeConfig(), pool: pool as never, signingKeys: new LocalDevSigningKeyProvider(), entraVerifier: null });

    const response = await app.inject({
      method: "POST",
      url: "/webhooks/stripe",
      headers: { "content-type": "application/json" },
      payload: "{}"
    });

    expect(response.statusCode).toBe(503);
    await app.close();
  });

  it("POST /webhooks/stripe returns 400 for an invalid signature", async () => {
    const pool = createAuthedPool();
    const app = buildApp({
      config: fakeConfig({ STRIPE_WEBHOOK_SECRET: "whsec_test_secret" }),
      pool: pool as never,
      signingKeys: new LocalDevSigningKeyProvider(),
      entraVerifier: null
    });

    const response = await app.inject({
      method: "POST",
      url: "/webhooks/stripe",
      headers: {
        "content-type": "application/json",
        "stripe-signature": "invalid"
      },
      payload: JSON.stringify({ id: "evt_test", object: "event", type: "ping" })
    });

    expect(response.statusCode).toBe(400);
    await app.close();
  });

  it("POST /webhooks/stripe durably accepts a verified event", async () => {
    const pool = createAuthedPool();
    const secret = "whsec_test_secret";
    const payload = JSON.stringify({
      id: "evt_test_webhook",
      object: "event",
      type: "customer.subscription.updated",
      livemode: false,
      created: 1_700_000_000,
      data: { object: { id: "sub_test" } }
    });
    const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret });

    const app = buildApp({
      config: fakeConfig({ STRIPE_WEBHOOK_SECRET: secret }),
      pool: pool as never,
      signingKeys: new LocalDevSigningKeyProvider(),
      entraVerifier: null
    });

    const response = await app.inject({
      method: "POST",
      url: "/webhooks/stripe",
      headers: {
        "content-type": "application/json",
        "stripe-signature": signature
      },
      payload
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ received: true });
    await app.close();
  });
});

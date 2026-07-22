import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";
import type { AppConfig } from "../config.js";
import { ApiError, sendError } from "../errors.js";
import { requireDeviceAuth } from "../auth/guard.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import {
  createStripeServices,
  isStripeBillingConfigured,
  isStripeWebhookConfigured,
  StripeWebhookConfigError,
  StripeWebhookVerificationError,
  verifyStripeWebhookEvent
} from "../billing/stripe.js";
import { recordStripeEventInbox } from "../billing/inbox.js";

const CheckoutSessionRequestSchema = z.strictObject({
  priceLookupKey: z.string().min(1)
});

function billingNotConfigured(reply: import("fastify").FastifyReply): void {
  sendError(
    reply,
    new ApiError("INTERNAL_ERROR", 501, "Stripe billing is not configured on this environment.")
  );
}

/**
 * Docs/contracts/openapi.yaml /billing/checkout-session, /billing/portal-session,
 * and /webhooks/stripe — Stage 7 foundation. Checkout/Portal return 501 until
 * STRIPE_SECRET_KEY is configured; webhook verifies signature and durably
 * records events when STRIPE_WEBHOOK_SECRET is configured.
 */
export function registerBillingRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider,
  config: AppConfig
): void {
  const stripeServices = createStripeServices(config);

  app.post("/billing/checkout-session", async (request, reply) => {
    await requireDeviceAuth(request, pool, keys);
    if (!isStripeBillingConfigured(config) || !stripeServices.client) {
      billingNotConfigured(reply);
      return;
    }

    const parsed = CheckoutSessionRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Invalid checkout session request."));
      return;
    }

    // Stage 7.2: map priceLookupKey → Stripe Price and create Checkout Session.
    sendError(reply, new ApiError("INTERNAL_ERROR", 501, "Checkout session creation is not implemented yet."));
  });

  app.post("/billing/portal-session", async (request, reply) => {
    await requireDeviceAuth(request, pool, keys);
    if (!isStripeBillingConfigured(config) || !stripeServices.client) {
      billingNotConfigured(reply);
      return;
    }

    // Stage 7.2: resolve billing_customers.stripe_customer_id and create Portal Session.
    sendError(reply, new ApiError("INTERNAL_ERROR", 501, "Portal session creation is not implemented yet."));
  });

  app.addContentTypeParser("application/json", { parseAs: "buffer" }, (request, body, done) => {
    if (request.url === "/webhooks/stripe") {
      done(null, body);
      return;
    }
    try {
      done(null, JSON.parse(body.toString("utf8")) as unknown);
    } catch (err) {
      done(err as Error, undefined);
    }
  });

  app.post("/webhooks/stripe", async (request, reply) => {
    if (!isStripeWebhookConfigured(config)) {
      sendError(
        reply,
        new ApiError("INTERNAL_ERROR", 503, "Stripe webhook ingestion is not configured on this environment.")
      );
      return;
    }

    const rawBody = request.body;
    if (!Buffer.isBuffer(rawBody)) {
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Invalid webhook payload."));
      return;
    }

    let event;
    try {
      const signatureHeader = request.headers["stripe-signature"];
      const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;
      event = verifyStripeWebhookEvent(stripeServices, rawBody, signature);
    } catch (err) {
      if (err instanceof StripeWebhookConfigError) {
        sendError(reply, new ApiError("INTERNAL_ERROR", 503, err.message));
        return;
      }
      if (err instanceof StripeWebhookVerificationError) {
        sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Invalid Stripe webhook signature."));
        return;
      }
      sendError(reply, new ApiError("VALIDATION_FAILED", 400, "Invalid Stripe webhook signature."));
      return;
    }

    const minimizedPayload = {
      id: event.id,
      type: event.type,
      livemode: event.livemode,
      created: event.created,
      objectId:
        typeof event.data.object === "object" && event.data.object != null && "id" in event.data.object
          ? String((event.data.object as { id: unknown }).id)
          : null
    };

    await recordStripeEventInbox(pool, {
      stripeEventId: event.id,
      eventType: event.type,
      payload: minimizedPayload
    });

    reply.code(200).send({ received: true });
  });
}

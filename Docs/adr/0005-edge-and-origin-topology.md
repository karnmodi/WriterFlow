# ADR-0005: Public edge is API Management; private origin is Container Apps

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

A consumer desktop app must reach WriterFlow's API over the public internet — a
literally private-only ingress is not achievable for this client shape
(`V2-ARCHITECTURE.md` §2). The implementable goal is one public, authenticated,
documented-to-the-app edge, with no public backend origin, database, Key Vault, or
model endpoint behind it.

## Decision

- **Edge:** Azure API Management Standard v2 at `apiwriterflow.aviusolutions.com`, validating
  **WriterFlow-issued** device tokens with generic `validate-jwt` against WriterFlow's
  own JWKS/issuer/audience (ADR-0012), applying request/rate limits, and disabling
  response buffering/body logging for SSE. (Entra tokens are validated only
  server-side by the web app; the Mac never presents an Entra token to this edge.)
- **Origin:** one TypeScript/Fastify API-orchestrator on Azure Container Apps in a
  workload-profiles environment with an internal VIP and public network access
  disabled at the environment level. The API app itself uses app-level `external`
  ingress (external to its Container Apps environment only); APIM reaches it
  through outbound VNet integration and private DNS.
- `/v2/webhooks/stripe` is a deliberate exception: raw-body Stripe signature
  verification instead of bearer-token validation, isolated from user routes.
- `/v2/device/authorize` and `/v2/device/token` (ADR-0011) are the device-pairing
  exceptions: unauthenticated but strictly rate-limited, protected by a short-lived
  single-use PKCE-bound `device_code` rather than a bearer token.

## Consequences

- Every Mac/user route is defense-in-depth: APIM JWT check, then repeated
  application-layer user/device/membership/entitlement authorization
  (`V2-ARCHITECTURE.md` §5.2).
- Azure Front Door Premium + WAF is explicitly deferred until multi-region routing,
  origin shielding at the gateway, or a specific WAF requirement justifies its
  cost.
- APIM Consumption tier is excluded — it does not support the long-running SSE this
  product requires.

## Revisit when

Multi-region routing, origin shielding, or WAF requirements justify Front Door
Premium; or sustained scale/specialized networking needs justify moving off
Container Apps to AKS.

import type { FastifyInstance } from "fastify";
import type { SigningKeyProvider } from "../jwt/keys.js";

/**
 * ADR-0012: publishes api.writerflow.app/.well-known/jwks.json. This is a
 * fixed RFC 8615 well-known path at the issuer's true root — it must stay
 * outside the /v2 versioned API path APIM otherwise fronts everything with,
 * so infra/apim/main needs a second, root-scoped API/operation forwarding
 * this exact path to the same backend (tracked as a Stage 5.2 infra
 * follow-up, not yet added to infra/bicep/modules/apim.bicep).
 */
export function registerJwksRoutes(app: FastifyInstance, keys: SigningKeyProvider): void {
  app.get("/.well-known/jwks.json", async () => keys.getPublicJwks());
}

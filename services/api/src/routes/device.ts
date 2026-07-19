import type { FastifyInstance } from "fastify";
import type pg from "pg";
import {
  DeviceAuthorizeRequestSchema,
  DeviceTokenRequestSchema,
  RefreshRequestSchema
} from "@writerflow/shared";
import { ApiError, sendError } from "../errors.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { authorizeDevice, pollDeviceToken, rotateRefreshToken } from "../pairing/service.js";

/**
 * Docs/contracts/openapi.yaml /device/authorize, /device/token,
 * /token/refresh — the three bearer-exempt pairing routes (ADR-0011,
 * ADR-0012). Registered without a /v2 prefix to match what
 * infra/apim/modules/apim.bicep's 'writerflow-v2' API forwards to the
 * backend once its own 'v2' path segment is stripped at the gateway.
 *
 * /device/approve is deliberately NOT implemented here yet — it requires
 * resolving how the website (a separate confidential-client app) proves its
 * own authenticated session to this API, which isn't specified anywhere in
 * V2-ARCHITECTURE.md/ADR-0011/ADR-0012 beyond "the bearerAuth here denotes
 * the web session, not a WriterFlow device token." That's a real open
 * design question, not something to invent silently on a security boundary.
 */
export function registerDeviceRoutes(
  app: FastifyInstance,
  pool: pg.Pool,
  keys: SigningKeyProvider,
  websiteBaseUrl: string
): void {
  app.post("/device/authorize", async (request, reply) => {
    const parsed = DeviceAuthorizeRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid device authorization request.");
    }
    const result = await authorizeDevice(pool, websiteBaseUrl, parsed.data);
    reply.code(200).send(result);
  });

  app.post("/device/token", async (request, reply) => {
    const parsed = DeviceTokenRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid device token request.");
    }
    const result = await pollDeviceToken(pool, keys, parsed.data.deviceCode, parsed.data.codeVerifier);
    if (result.kind === "issued") {
      reply.code(200).send({
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresIn: result.expiresIn,
        deviceId: result.deviceId
      });
      return;
    }
    if (result.kind === "invalid_grant") {
      sendError(reply, new ApiError("AUTH_INVALID", 401, "Invalid device pairing grant."));
      return;
    }
    reply.code(202).send({ status: result.status });
  });

  app.post("/token/refresh", async (request, reply) => {
    const parsed = RefreshRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid refresh request.");
    }
    const result = await rotateRefreshToken(pool, keys, parsed.data.refreshToken);
    if (result.kind === "invalid") {
      sendError(reply, new ApiError("AUTH_INVALID", 401, "Invalid or reused refresh token."));
      return;
    }
    reply.code(200).send({
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
      deviceId: result.deviceId
    });
  });
}

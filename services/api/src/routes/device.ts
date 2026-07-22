import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";
import {
  DeviceAuthorizeRequestSchema,
  DeviceTokenRequestSchema,
  RefreshRequestSchema
} from "@writerflow/shared";
import { ApiError, sendError } from "../errors.js";
import type { SigningKeyProvider } from "../jwt/keys.js";
import { authorizeDevice, pollDeviceToken, rotateRefreshToken } from "../pairing/service.js";
import { approveDevice } from "../pairing/approve.js";
import { verifyWebSessionToken, entraIdentityFromWebSessionClaims } from "../jwt/issuer.js";

const DeviceApproveRequestSchema = z.strictObject({
  userCode: z.string().min(1)
});

/**
 * Docs/contracts/openapi.yaml /device/authorize, /device/token,
 * /token/refresh, /device/approve (ADR-0011, ADR-0012, and Stage 5.2's
 * "second token issuer" decision for /device/approve). The first three are
 * bearer-exempt; /device/approve requires a WriterFlow web-session token
 * (POST /v2/web-session/token), never a device access token — enforced here
 * by verifying against the web-session audience specifically, so a device
 * token can never be replayed against this endpoint. Registered without a
 * /v2 prefix to match what infra/apim/modules/apim.bicep's 'writerflow-v2'
 * API forwards to the backend once its own 'v2' path segment is stripped at
 * the gateway.
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

  app.post("/device/approve", async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      sendError(reply, new ApiError("AUTH_REQUIRED", 401, "A web-session token is required."));
      return;
    }
    const webSessionToken = authHeader.slice("Bearer ".length);
    const verified = await verifyWebSessionToken(keys, webSessionToken);
    if (!verified.ok) {
      sendError(reply, new ApiError("AUTH_INVALID", 401, "Invalid or expired web-session token."));
      return;
    }

    const parsed = DeviceApproveRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new ApiError("VALIDATION_FAILED", 400, "Invalid device approve request.");
    }

    const result = await approveDevice(
      pool,
      entraIdentityFromWebSessionClaims(verified.claims),
      parsed.data.userCode
    );
    if (result.kind === "invalid_user_code") {
      sendError(reply, new ApiError("VALIDATION_FAILED", 404, "Unknown, expired, or already-consumed user code."));
      return;
    }
    if (result.kind === "account_disabled") {
      sendError(reply, new ApiError("AUTH_INVALID", 403, "This account is disabled."));
      return;
    }
    reply.code(200).send(result.snapshot);
  });
}

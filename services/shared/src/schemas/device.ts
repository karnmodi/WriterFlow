import { z } from "zod";

/** Mirrors Docs/contracts/openapi.yaml's Device* / RefreshRequest schemas. */

export const DeviceAuthorizeRequestSchema = z.strictObject({
  installId: z.string().min(1).max(256),
  deviceLabel: z.string().max(128).nullable().optional(),
  codeChallenge: z.string().length(43),
  codeChallengeMethod: z.literal("S256")
});
export type DeviceAuthorizeRequest = z.infer<typeof DeviceAuthorizeRequestSchema>;

export const DeviceAuthorizeResponseSchema = z.strictObject({
  deviceCode: z.string(),
  userCode: z.string(),
  verificationUri: z.url(),
  verificationUriComplete: z.url(),
  interval: z.number().int().positive(),
  expiresIn: z.number().int().positive()
});
export type DeviceAuthorizeResponse = z.infer<typeof DeviceAuthorizeResponseSchema>;

export const DeviceTokenRequestSchema = z.strictObject({
  deviceCode: z.string().min(1),
  codeVerifier: z.string().min(43).max(128)
});
export type DeviceTokenRequest = z.infer<typeof DeviceTokenRequestSchema>;

export const DeviceTokenResponseSchema = z.strictObject({
  accessToken: z.string(),
  refreshToken: z.string(),
  expiresIn: z.number().int().positive(),
  deviceId: z.string()
});
export type DeviceTokenResponse = z.infer<typeof DeviceTokenResponseSchema>;

export const DeviceTokenPendingStatusSchema = z.enum([
  "authorization_pending",
  "slow_down",
  "access_denied",
  "expired_token"
]);
export type DeviceTokenPendingStatus = z.infer<typeof DeviceTokenPendingStatusSchema>;

export const DeviceTokenPendingSchema = z.strictObject({
  status: DeviceTokenPendingStatusSchema
});
export type DeviceTokenPending = z.infer<typeof DeviceTokenPendingSchema>;

export const RefreshRequestSchema = z.strictObject({
  refreshToken: z.string().min(1)
});
export type RefreshRequest = z.infer<typeof RefreshRequestSchema>;

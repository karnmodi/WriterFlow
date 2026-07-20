import { randomUUID } from "node:crypto";
import type pg from "pg";
import {
  WRITERFLOW_REFRESH_TOKEN_TTL_SECONDS,
  type DeviceAuthorizeRequest,
  type DeviceTokenPendingStatus
} from "@writerflow/shared";
import { withDeviceBootstrapLookup } from "../db.js";
import { generateOpaqueToken, generateUserCode, hashToken } from "../crypto/tokens.js";
import { verifyPkce } from "../crypto/pkce.js";
import { mintAccessToken } from "../jwt/issuer.js";
import type { SigningKeyProvider } from "../jwt/keys.js";

const DEVICE_AUTHORIZATION_TTL_SECONDS = 15 * 60;
const POLL_INTERVAL_SECONDS = 5;
const DEFAULT_SCOPE = "device";

export interface AuthorizeDeviceResult {
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  verificationUriComplete: string;
  interval: number;
  expiresIn: number;
}

export interface AuthorizeDeviceOptions {
  /** Overridable only for tests — production always uses POLL_INTERVAL_SECONDS. */
  intervalSeconds?: number;
}

/**
 * POST /v2/device/authorize — Docs/contracts/openapi.yaml, ADR-0011.
 * device_authorizations has no organization_id/RLS (it exists before any
 * account is resolved), so this needs no tenant/bootstrap context.
 */
export async function authorizeDevice(
  db: pg.Pool,
  verificationBaseUrl: string,
  input: DeviceAuthorizeRequest,
  options: AuthorizeDeviceOptions = {}
): Promise<AuthorizeDeviceResult> {
  const deviceCode = generateOpaqueToken();
  const deviceCodeHash = hashToken(deviceCode);
  const intervalSeconds = options.intervalSeconds ?? POLL_INTERVAL_SECONDS;

  // user_code has a UNIQUE constraint; the 31^8 space makes collisions rare
  // but not impossible — retry a handful of times rather than fail the
  // whole pairing attempt on one unlucky draw.
  for (let attempt = 0; attempt < 5; attempt++) {
    const userCode = generateUserCode();
    try {
      await db.query(
        `INSERT INTO device_authorizations
           (device_code_hash, user_code, install_id, device_label, code_challenge, code_challenge_method, interval_seconds, expires_at)
         VALUES ($1, $2, $3, $4, $5, 'S256', $6, now() + ($7 || ' seconds')::interval)`,
        [
          deviceCodeHash,
          userCode,
          input.installId,
          input.deviceLabel ?? null,
          input.codeChallenge,
          intervalSeconds,
          DEVICE_AUTHORIZATION_TTL_SECONDS
        ]
      );
      return {
        deviceCode,
        userCode,
        verificationUri: `${verificationBaseUrl}/pair`,
        verificationUriComplete: `${verificationBaseUrl}/pair?user_code=${encodeURIComponent(userCode)}`,
        interval: intervalSeconds,
        expiresIn: DEVICE_AUTHORIZATION_TTL_SECONDS
      };
    } catch (err) {
      if (isUniqueViolation(err)) continue;
      throw err;
    }
  }
  throw new Error("failed to allocate a unique user_code after 5 attempts");
}

function isUniqueViolation(err: unknown): boolean {
  return typeof err === "object" && err !== null && "code" in err && (err as { code?: string }).code === "23505";
}

export type PollDeviceTokenResult =
  | { kind: "issued"; accessToken: string; refreshToken: string; expiresIn: number; deviceId: string }
  | { kind: "pending"; status: DeviceTokenPendingStatus }
  | { kind: "invalid_grant" };

interface DeviceAuthorizationRow {
  id: string;
  code_challenge: string;
  status: string;
  approved_device_id: string | null;
  last_polled_at: Date | null;
  interval_seconds: number;
  expires_at: Date;
}

/**
 * POST /v2/device/token — Docs/contracts/openapi.yaml, ADR-0012. Runs under
 * withDeviceBootstrapLookup because the `devices` row it must read/update
 * (approved_device_id, resolved only inside this function) is RLS-protected
 * by organization_id and no tenant is known yet — see migration 010.
 */
export async function pollDeviceToken(
  db: pg.Pool,
  keys: SigningKeyProvider,
  deviceCode: string,
  codeVerifier: string
): Promise<PollDeviceTokenResult> {
  const deviceCodeHash = hashToken(deviceCode);
  return withDeviceBootstrapLookup(db, async (client) => {
    const { rows } = await client.query<DeviceAuthorizationRow>(
      `SELECT id, code_challenge, status, approved_device_id, last_polled_at, interval_seconds, expires_at
       FROM device_authorizations WHERE device_code_hash = $1 FOR UPDATE`,
      [deviceCodeHash]
    );
    const row = rows[0];
    if (!row) {
      return { kind: "pending", status: "expired_token" };
    }

    if (row.status === "consumed" || row.status === "expired" || new Date(row.expires_at) < new Date()) {
      if (row.status === "pending" || row.status === "approved") {
        await client.query(`UPDATE device_authorizations SET status = 'expired' WHERE id = $1`, [row.id]);
      }
      return { kind: "pending", status: "expired_token" };
    }

    if (row.status === "denied") {
      return { kind: "pending", status: "access_denied" };
    }

    if (row.last_polled_at) {
      const elapsedMs = Date.now() - new Date(row.last_polled_at).getTime();
      if (elapsedMs < row.interval_seconds * 1000) {
        return { kind: "pending", status: "slow_down" };
      }
    }
    await client.query(`UPDATE device_authorizations SET last_polled_at = now() WHERE id = $1`, [row.id]);

    if (row.status === "pending") {
      return { kind: "pending", status: "authorization_pending" };
    }

    // status === 'approved'
    if (!verifyPkce(codeVerifier, row.code_challenge)) {
      return { kind: "invalid_grant" };
    }
    const deviceId = row.approved_device_id;
    if (!deviceId) {
      // Guarded by device_authorizations' CHECK constraint — unreachable.
      return { kind: "invalid_grant" };
    }

    const deviceResult = await client.query<{
      user_id: string;
      organization_id: string;
      revoked_at: Date | null;
      user_status: string;
    }>(
      `SELECT d.user_id, d.organization_id, d.revoked_at, u.status AS user_status
       FROM devices d JOIN users u ON u.id = d.user_id
       WHERE d.id = $1`,
      [deviceId]
    );
    const device = deviceResult.rows[0];
    if (!device || device.revoked_at || device.user_status !== "active") {
      return { kind: "invalid_grant" };
    }

    await client.query(`UPDATE device_authorizations SET status = 'consumed' WHERE id = $1`, [row.id]);

    const { token: accessToken, expiresIn } = await mintAccessToken(keys, {
      userId: device.user_id,
      deviceId,
      organizationId: device.organization_id,
      scope: DEFAULT_SCOPE
    });

    const refreshToken = generateOpaqueToken();
    const familyId = randomUUID();
    await client.query(
      `INSERT INTO refresh_tokens (device_id, family_id, token_hash, expires_at)
       VALUES ($1, $2, $3, now() + ($4 || ' seconds')::interval)`,
      [deviceId, familyId, hashToken(refreshToken), WRITERFLOW_REFRESH_TOKEN_TTL_SECONDS]
    );
    await client.query(`UPDATE devices SET last_token_issued_at = now(), last_seen_at = now() WHERE id = $1`, [
      deviceId
    ]);

    return { kind: "issued", accessToken, refreshToken, expiresIn, deviceId };
  });
}

export type RefreshTokenResult =
  | { kind: "issued"; accessToken: string; refreshToken: string; expiresIn: number; deviceId: string }
  | { kind: "invalid" };

interface RefreshTokenRow {
  id: string;
  device_id: string;
  family_id: string;
  superseded_at: Date | null;
  revoked_at: Date | null;
  expires_at: Date;
}

/**
 * POST /v2/token/refresh — rotating refresh with reuse detection
 * (V2-ARCHITECTURE.md §5.1 step 8). Presenting an already-rotated
 * (superseded) token revokes its entire family, not just this one token.
 * Also runs under withDeviceBootstrapLookup — same bootstrap problem as
 * pollDeviceToken: the caller has only an opaque refresh token, not a
 * resolved tenant.
 */
export async function rotateRefreshToken(
  db: pg.Pool,
  keys: SigningKeyProvider,
  presentedToken: string
): Promise<RefreshTokenResult> {
  const presentedHash = hashToken(presentedToken);
  return withDeviceBootstrapLookup(db, async (client) => {
    const { rows } = await client.query<RefreshTokenRow>(
      `SELECT id, device_id, family_id, superseded_at, revoked_at, expires_at
       FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
      [presentedHash]
    );
    const row = rows[0];
    if (!row || row.revoked_at) {
      return { kind: "invalid" };
    }

    if (row.superseded_at) {
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL`,
        [row.family_id]
      );
      return { kind: "invalid" };
    }

    if (new Date(row.expires_at) < new Date()) {
      return { kind: "invalid" };
    }

    const deviceResult = await client.query<{
      user_id: string;
      organization_id: string;
      revoked_at: Date | null;
      user_status: string;
    }>(
      `SELECT d.user_id, d.organization_id, d.revoked_at, u.status AS user_status
       FROM devices d JOIN users u ON u.id = d.user_id
       WHERE d.id = $1`,
      [row.device_id]
    );
    const device = deviceResult.rows[0];
    if (!device || device.revoked_at || device.user_status !== "active") {
      return { kind: "invalid" };
    }

    // Mark the old row superseded BEFORE inserting the new one — both rows
    // would otherwise briefly satisfy refresh_tokens_one_active_per_family's
    // partial unique index (superseded_at IS NULL AND revoked_at IS NULL)
    // at once, and Postgres checks non-deferred unique constraints per
    // statement, not at COMMIT.
    await client.query(`UPDATE refresh_tokens SET superseded_at = now() WHERE id = $1`, [row.id]);
    const newRefreshToken = generateOpaqueToken();
    await client.query(
      `INSERT INTO refresh_tokens (device_id, family_id, token_hash, expires_at)
       VALUES ($1, $2, $3, now() + ($4 || ' seconds')::interval)`,
      [row.device_id, row.family_id, hashToken(newRefreshToken), WRITERFLOW_REFRESH_TOKEN_TTL_SECONDS]
    );
    await client.query(`UPDATE devices SET last_seen_at = now() WHERE id = $1`, [row.device_id]);

    const { token: accessToken, expiresIn } = await mintAccessToken(keys, {
      userId: device.user_id,
      deviceId: row.device_id,
      organizationId: device.organization_id,
      scope: DEFAULT_SCOPE
    });

    return { kind: "issued", accessToken, refreshToken: newRefreshToken, expiresIn, deviceId: row.device_id };
  });
}

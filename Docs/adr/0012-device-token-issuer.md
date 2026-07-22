# ADR-0012: The WriterFlow backend is the device-token issuer

**Status:** Accepted
**Date:** 2026-07-18
**Phase:** 5 — Cloud foundation
**Related:** ADR-0011 (browser-mediated auth), ADR-0005 (edge/origin topology)

## Context

Because auth moves to the browser and the Mac pairs via a device flow (ADR-0011), the
app must hold *some* durable credential to call `apiwriterflow.aviusolutions.com`. Two options
exist: hand the device the Entra tokens, or have WriterFlow mint its own. Handing
Entra tokens to the device couples the app to Entra's refresh lifetimes (email OTP is
~24h), leaks Entra tokens onto an unsigned client, and forces the app back into being
an Entra client. Minting WriterFlow tokens keeps Entra strictly browser-side.

## Decision

The WriterFlow backend is an **OAuth-style token issuer for paired devices**:

- **Access token:** short-lived (~15 min) asymmetrically-signed JWT (`iss` =
  `https://apiwriterflow.aviusolutions.com`, `aud` = the WriterFlow API), whose signing key lives
  in Key Vault. Public keys are published at `apiwriterflow.aviusolutions.com/.well-known/jwks.json`.
- **Refresh token:** opaque, high-entropy, stored **hashed** and bound to one
  `devices` row; **rotated on every use** with reuse detection (a replayed old
  refresh token revokes the session family).
- **APIM `validate-jwt` validates WriterFlow-issued tokens** against WriterFlow's own
  JWKS/issuer/audience — not Entra tokens (this amends ADR-0005's edge note). Entra
  tokens are validated only server-side by the web app during sign-in.
- Token/session claims carry `(user_id, organization_id, device_id)`; the application
  layer still re-resolves user status, membership, non-revoked device, and entitlement
  on every request (ADR-0005 defense-in-depth is unchanged).
- Revocation: `DELETE /v2/devices/{id}`, identity-session revoke, and account disable
  all invalidate the device's refresh family; short access-token lifetime bounds the
  stolen-access-token window.

## Consequences

- Net-new backend responsibility: signing-key generation/rotation in Key Vault, a JWKS
  endpoint, refresh-token hashing/rotation/reuse-detection, and a `device_sessions`
  concept alongside `devices`. These are added to Stage 5.2 and the threat model.
- APIM policy changes from validating Entra metadata to validating WriterFlow's OIDC
  metadata; the Entra-specific `validate-jwt` config in ADR-0005/§5.2 applies to the
  **web app's** Entra validation, not the Mac API edge.
- The device flow's `/v2/device/authorize` and `/v2/device/token` are the only
  unauthenticated user-facing routes; everything else requires a valid WriterFlow
  access token plus application authorization.
- No shared/reusable service credential ships in the app — the device refresh token is
  per-device, revocable, and useless without the backend (golden rule 5 preserved).

## Revisit when

A supported native token-binding standard (DPoP/mTLS) becomes viable and warrants
binding device tokens to a device-held key, or federation requirements make
re-fronting Entra tokens preferable.

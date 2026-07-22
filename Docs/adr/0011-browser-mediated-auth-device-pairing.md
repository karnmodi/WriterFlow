# ADR-0011: Auth and membership happen in the browser; the Mac pairs via a device flow

**Status:** Accepted
**Date:** 2026-07-18
**Phase:** 5 — Cloud foundation
**Supersedes:** ADR-0002 (in-app MSAL Authorization Code + PKCE)

## Context

ADR-0002 put the OAuth flow inside the Mac app (MSAL, Authorization Code + PKCE via
`ASWebAuthenticationSession`). That requires a registered Entra redirect URI and
MSAL's shared Keychain access group, both of which want a stable Apple signing
identity — the primary driver of ADR-0008's Developer ID mandate.

The product now keeps **sign-in, membership, and payment in the web browser** and
passes a session to the Mac afterward. A server-side web app is a *confidential*
OAuth client and is a strictly better Entra citizen than an embedded public client.
Removing MSAL from the app also removes the redirect-URI and Keychain-access-group
dependencies that made a Developer ID necessary (ADR-0010).

## Decision

- The **WriterFlow web app is the only Entra External ID client** (confidential,
  server-side). It runs Entra sign-in, provisions the user/personal
  organization/membership, and hosts all Stripe membership management (ADR-0009 keeps
  paid enforcement out of Phase 5, but the browser is the permanent home for it).
- The **Mac app is not an OAuth client** and embeds no MSAL, no Entra client ID, no
  redirect URI, and no client secret.
- The Mac obtains a session through a **device-authorization pairing flow**
  (RFC 8628-shaped, re-implemented at WriterFlow's own API layer):
  1. The app calls `POST /v2/device/authorize` (no bearer; strict rate limit; carries
     client version, opaque install ID, and a PKCE `code_challenge`) and receives
     `device_code`, a short human `user_code`, `verification_uri`,
     `verification_uri_complete`, `interval`, and `expires_in`.
  2. The user approves in the browser — the **happy path** is a deep link /
     `verification_uri_complete` (`https://writerflow.aviusolutions.com/pair?user_code=…`), and the
     **fallback** is typing the `user_code` at `writerflow.aviusolutions.com/pair`. After Entra
     sign-in (and membership if upgrading), the web calls `POST /v2/device/approve`
     with the `user_code` under its authenticated session.
  3. The app polls `POST /v2/device/token` with `device_code` + PKCE `code_verifier`,
     receiving `authorization_pending` / `slow_down` / `expired_token` /
     `access_denied` until success returns WriterFlow-minted tokens (ADR-0012).
- A `writerflow://paired` deep link may foreground the app to stop the polling wait,
  but it **carries no token or secret** — token transfer is only ever the polled
  `/v2/device/token` response bound to the app's PKCE verifier. This is why an
  unsigned/ad-hoc app is safe here: the custom scheme is a UX hint, not a credential
  channel.

## Consequences

- No `ASWebAuthenticationSession`, no registered redirect URI, and no Keychain access
  group are needed on the Mac — the exact dependencies that forced ADR-0008 are gone.
- The Mac stores only WriterFlow-issued tokens (ADR-0012) in its own Keychain item.
  It never holds an Entra token.
- Internal identity remains `(issuer, subject)`, resolved by the web/backend from the
  Entra token (ADR-0001), never email.
- `/v2/device/authorize` and `/v2/device/token` are unauthenticated-but-rate-limited
  edge exceptions alongside `/v2/webhooks/stripe` (ADR-0005); the `device_code` is a
  short-lived, single-use, PKCE-bound secret, not a bearer credential.
- The device-pairing surface is net-new attack surface (code phishing, polling abuse)
  and is added to the threat model.
- `PRD-V2.md` §6.2 (“Sign in on a new Mac”) and `V2-ARCHITECTURE.md` §5 are rewritten
  around pairing instead of MSAL.

## Revisit when

Entra ships supported native token binding (DPoP/mTLS) *and* an Apple Developer ID is
acquired anyway, making an in-app flow worth its added client complexity — or a
platform requires the app to be a first-class OAuth client.

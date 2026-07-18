# ADR-0002: Native auth flow is Authorization Code + PKCE, no client secret

**Status:** Superseded by ADR-0011 (2026-07-18)
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

> **Superseded.** WriterFlow no longer runs OAuth inside the Mac app. Auth and
> membership happen in the browser (a confidential Entra client), and the Mac obtains
> a WriterFlow-minted session through a device-authorization pairing flow (ADR-0011,
> ADR-0012). The no-embedded-secret / public-client principle below still holds and is
> why device-pairing tokens, not an app secret, prove nothing about client identity;
> the concrete MSAL/`ASWebAuthenticationSession` mechanics are replaced. Retained for
> context.

## Context

WriterFlow.app is distributed to end users; any secret embedded in the binary is
extractable. The app must still prove enough about the requesting client to satisfy
native OAuth best practice without inventing custom cryptography.

## Decision

Use OAuth 2.0 Authorization Code with PKCE, run through the system browser via
`ASWebAuthenticationSession` and MSAL's macOS support. The macOS app registration
carries no client secret. Silent token refresh runs only when an explicit user
action needs the API (opening an account surface, or an explicit click/hotkey
operation) — never on passive typing or focus events.

## Consequences

- The app is architecturally a public client. A client ID is not a secret and must
  never be treated as proof of app identity by the backend.
- MSAL owns the token cache in its supported app-specific Keychain group, separate
  from WriterFlow's own local database key (ADR-0004).
- A device ID header and code signing reduce tampered-client risk but are not
  authentication; the backend's authorization boundary is the validated bearer
  token plus server-side device/membership/entitlement checks
  (`V2-ARCHITECTURE.md` §5.2–5.3).
- No embedded shared secret, custom signing scheme, or bespoke crypto is used to
  "prove" native app identity.

## Revisit when

Entra/MSAL ship a supported token-binding standard (DPoP or mTLS) with a validated
certificate/key lifecycle on macOS, and product risk justifies adding it.

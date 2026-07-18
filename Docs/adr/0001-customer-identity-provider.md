# ADR-0001: Customer identity provider is Microsoft Entra External ID

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

V2 needs a durable identity for real users without embedding a client secret in the
Mac app, and without WriterFlow building its own password/credential store (a stated
non-goal in `PRD-V2.md` §4). WriterFlow already standardizes on Azure for its model
plane, so a consumer-identity product on the same platform minimizes cross-cloud
networking and lets one team operate identity, database, and model access together.

## Decision

Use Microsoft Entra External ID (CIAM) as the managed customer identity provider.
Initial sign-in methods are email one-time passcode plus one social provider.

**Amended 2026-07-18 (ADR-0011/0012):** the **WriterFlow web app** is the only Entra
client — a confidential, server-side registration that runs sign-in and membership.
The Mac app is **not** an Entra/OAuth client; it pairs to a browser-completed session
and calls the API with a WriterFlow-minted token. The API edge therefore validates
**WriterFlow-issued** tokens (ADR-0012), while Entra tokens are validated only
server-side by the web app.

## Consequences

- No password hashes, reset flows, or credential storage are built or owned by
  WriterFlow.
- Sign-in happens in the system browser against the web app, which avoids a native
  password UI and follows native best current practice (RFC 8252) without the Mac app
  being an OAuth client at all.
- WriterFlow's internal identity key is `(issuer, subject)`, never email — see
  ADR-0002 and `V2-ARCHITECTURE.md` §8.1.
- Email OTP's documented short refresh-token lifetime (~24h) must be tested in the
  signed app before it can be the recommended default; the social provider is the
  fallback recommendation if OTP forces daily reauthentication.
- Adding Apple/Google/Microsoft/MFA/enterprise federation later does not change this
  ADR or the internal user key.

## Revisit when

Required sign-in UX (e.g., passkeys, enterprise SSO/SCIM ahead of schedule) or
provider support is materially weaker than an alternative managed CIAM platform.

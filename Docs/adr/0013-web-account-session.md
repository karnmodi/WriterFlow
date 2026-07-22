# ADR-0013: Durable web-account session separate from Mac device tokens

**Status:** Accepted
**Date:** 2026-07-22
**Phase:** 5 — Cloud foundation (Stage 5.2+ account surface)

## Context

Stage 5.2 wired real Entra sign-in for `/pair` device approval. That flow mints a
**5-minute** WriterFlow `web-session` JWT (audience `…/web-session`) held only in the
website server's memory for one `POST /device/approve` call. The browser never receives
a durable session — returning visitors cannot see account status, sign out, or skip
Microsoft re-auth when pairing again.

The Mac app holds its own WriterFlow **device** access + refresh tokens (ADR-0012).
Product policy requires these sessions stay independent: an expired web or Entra session
must not force Mac re-pair, and Mac sign-out must not clear the website cookie.

## Decision

Introduce a third WriterFlow-minted credential — the **web-account token**
(audience `https://apiwriterflow.aviusolutions.com/web-account`, ~1 hour):

| Credential | Audience | Holder | Lifetime | Purpose |
|---|---|---|---|---|
| Web-session (pairing bridge) | `…/web-session` | Website server only | 5 min | `POST /device/approve` |
| Web-account | `…/web-account` | Website httpOnly cookie | ~1 h | Account UI, `/web/me`, bridge to pairing |
| Device access | `…` (API) | Mac Keychain | ~15 min | Mac API routes |
| Device refresh | opaque | Mac Keychain | ~30 d | Rotate device access |

- **Mint on Microsoft sign-in**, not on passive page visit. The website stores the
  web-account JWT in an httpOnly `wf_web_account` cookie after Entra callback.
- **`POST /web-account/token`** verifies the Entra ID token (same as
  `/web-session/token`), **provisions the user/org if needed** (without creating a
  device), and returns the web-account JWT.
- **`GET /web/me`** returns account status for the web-account bearer (no device row).
- **`POST /web-session/bridge`** accepts a web-account bearer and mints a fresh 5-minute
  web-session token so `/pair` can approve a device without re-prompting Entra when the
  user is already web-signed-in.
- **Website sign-out** clears WriterFlow cookies and redirects through Entra's
  `end_session_endpoint` (Microsoft logout). Mac device tokens are unaffected.
- Entra ID tokens are never stored in the browser except a short-lived httpOnly
  `wf_entra_id_token_hint` used only as `id_token_hint` for logout.

## Consequences

- Three WriterFlow audiences share one JWKS/signing infrastructure (ADR-0012).
- `/pair` establishes a web-account cookie as a side effect of Entra sign-in so the next
  `/account` visit shows logged-in state.
- Stripe membership UI can authenticate with the same web-account cookie later.
- Mac `signOut()` and website sign-out remain orthogonal operations.

## Related

- ADR-0011 (browser-mediated pairing)
- ADR-0012 (device-token issuer)
- V2-ARCHITECTURE.md §5.1 (web account session addendum)

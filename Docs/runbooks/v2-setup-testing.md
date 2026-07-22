# WriterFlow V2 — Setup & Testing Runbook

Phase 5 (V2 cloud foundation) only. What's actually built as of Stage 5.2, what still
needs Azure/Entra setup, and the exact steps to open the app and pair a real account
yourself — for free, today, before spending anything on cloud infrastructure.

## Status

| Piece | Status |
|---|---|
| Backend pairing + account API | Done — verified against real local Postgres |
| Mac app — pairing & Account tab | Done |
| Website `/pair` sign-in | **Done (2026-07-22)** — real Entra sign-in, verified end to end against a live tenant |
| Azure infrastructure (Bicep) | Written, not deployed |
| Entra External ID tenant | Created |

**Bottom line:** the full flow works now. Once your Entra tenant and `.env.services`/
`website/.env.local` are set up (steps 1–3 below), the actual production UI — Dashboard
→ Account → **Sign In** — opens a real browser, runs a real Microsoft sign-in, and
finishes pairing automatically, with no manual `curl` steps. Section A below is the
quick version now that it's real; Section A.1 keeps the old manual step-by-step for
diagnosing a failure or testing without a Mac app build at all. **Track B** is still the
optional, paid step of putting this on real Azure infrastructure.

---

## A. The real flow (quickest path)

1. Complete steps 1–3 below once (create the Entra tenant, register the app, fetch its
   metadata) if you haven't already.
2. Set `ENTRA_TENANT_ISSUER`/`ENTRA_JWKS_URI`/`ENTRA_WEB_CLIENT_ID` in repo-root
   `.env.services`, and the same plus `ENTRA_WEB_CLIENT_SECRET`/`PAIR_REDIRECT_URI` in
   `website/.env.local` (see the env reference table at the bottom — `website/lib/
   entra.ts` reads these).
3. Start Postgres, `npm run dev --workspace services/api` (repo root), and `npm run dev`
   inside `website/`.
4. `WRITERFLOW_API_BASE_URL=http://localhost:8080` in a repo-root `.env`, then `make run`
   for the Mac app.
5. Open **Dashboard → Account** in the app and click **Sign In**. A browser opens to the
   real `/pair` page; sign in with Microsoft. The tab shows "Device approved," and the
   Dashboard finishes signing in within a few seconds on its own.

If any step fails, `website`'s dev server logs the real Entra error
(`console.error("pair/callback failed:", ...)` in `app/pair/callback/route.ts`) — check
that first. Section A.1 below walks the same flow by hand, one HTTP call at a time,
which is often faster for isolating *which* step is failing than reasoning about the
whole app.

### A.1 Manual/diagnostic version

Everything runs on your own machine: local Postgres, the API's dev server, and the Mac
app built from source. The only cloud dependency is the Entra tenant itself, which costs
nothing to create or sign into at this scale. This walks the same flow the real UI now
does automatically, one HTTP call at a time — mainly useful for isolating a failure, or
for testing without building the Mac app at all.

### 1. Create the Entra External ID (CIAM) tenant

In the [Azure portal](https://portal.azure.com), search for **"Microsoft Entra ID"** →
**Manage tenants** → **Create** → choose **External configuration** (this is the CIAM
tenant type WriterFlow's ADR-0001/0011 specify — separate from your own staff/work Entra
tenant). Give it any tenant name and a subdomain, e.g. `writerflow-dev`. Creation is
free.

- [ ] Tenant created, switched into it in the portal

### 2. Register the web app in that tenant

Inside the new tenant: **App registrations** → **New registration**. Name it
`writerflow-web-dev`. Under **Redirect URI**, add a **Single-page application (SPA)**
platform with redirect URI `https://jwt.ms` — Microsoft's own token-inspection page.
That's a deliberate stand-in for the real `/pair` callback while it's still a stub;
swap it for `writerflow.aviusolutions.com/pair` once that page actually signs people in.

Add sign-in methods under **External Identities**. Email OTP and Microsoft are the
baseline; Google (and other social IdPs) must be both **configured** and **added to
the user flow**, or they never appear on the hosted sign-in page.

1. **External Identities → All identity providers → Google → Configure** — paste the
   Google Cloud OAuth Client ID and Client secret, Save.
2. **External Identities → User flows → (your sign-up/sign-in flow) → Identity providers**
   — enable **Google** (and Email OTP / Microsoft as needed) → Save.
3. On the same user flow, under **Applications**, ensure **writerflow-web** is listed
   so every visitor using `/auth/start` or `/pair/start` gets that experience.
4. **Do not expect built-in Google ↔ email-OTP auto-link.** Entra External ID’s
   hosted user flow treats each IdP as a separate signup. If someone first signs up
   with Google, then enters the same address for email OTP, Entra shows
   **“An account with that email address already exists”** and **does not send the
   OTP** — that is Microsoft’s conflict check, not a WriterFlow bug. Tell users to
   pick **Google** (or whichever method created the account). WriterFlow still links
   same-issuer Entra subjects that share a verified email in
   `services/api/src/account/identity.ts` (`resolveOrLinkUserFromEntra`) after a
   successful token exchange; that cannot force Entra to email a code on a blocked
   signup.
5. **Company branding (logo on the Enter-code / IdP screens):** those pages are
   Microsoft-hosted. Polish them in the external tenant:
   **Microsoft Entra admin center → Company branding → Edit** (or **Branding themes**).
   Upload:
   - Banner / header logo: `website/public/brand/writerflow-entra-header.png` (280×60)
   - Square logo: `website/public/brand/writerflow-entra-square.png` (240×240)
   - Optional: set page background to `#f4f1e9` and primary button to `#1428ff` to
     match the marketing site. Favicon can reuse the square mark.
   See [Customize branding for customers](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-customize-branding-customers).

WriterFlow does not filter IdPs — the Entra hosted UI shows whatever the user flow
enables. No app code change is required for Google.

- [ ] App registered, redirect URIs include `/pair/callback` and `/auth/callback`
- [ ] Copied the **Application (client) ID** — you'll need it twice below
- [ ] Email OTP enabled on the user flow
- [ ] (Optional) Microsoft social enabled on the user flow
- [ ] (Optional) Google IdP configured **and** enabled on the user flow for all users
- [ ] writerflow-web application attached to that user flow
- [ ] Company branding logo uploaded from `website/public/brand/`
- [ ] Understood: OTP is not sent when Entra reports the email already exists via another IdP

### 3. Fetch the tenant's OpenID metadata

This gives you the exact `issuer` and `jwks_uri` values — don't guess these, a mismatch
makes token verification fail silently.

```
https://<your-tenant-subdomain>.ciamlogin.com/<your-tenant-subdomain>.onmicrosoft.com/v2.0/.well-known/openid-configuration
```

Open that URL and note two fields from the JSON: `issuer` and `jwks_uri`.

Don't be thrown if they use different subdomain forms — Microsoft's own metadata
document does this legitimately: `issuer` normalizes to the tenant-ID subdomain
(`<tenant-id>.ciamlogin.com/...`) while `jwks_uri` may come back on the tenant-name
subdomain (`<tenant-name>.ciamlogin.com/...`). Verified directly against a real tenant:
both subdomain forms of the JWKS endpoint return HTTP 200 with the identical set of key
IDs, and `jose`'s `createRemoteJWKSet` fetches whatever URL you give it — so this is
cosmetic, not a bug. Just copy both fields exactly as the JSON gives them; don't
"fix" them to match each other.

- [ ] Copied `issuer`
- [ ] Copied `jwks_uri`

### 4. Start local Postgres and run migrations

```bash
# repo root
docker compose up -d postgres

cd services/api
DATABASE_URL="postgres://writerflow_migrator:writerflow_migrator_dev_only@localhost:5432/writerflow" \
  npx node-pg-migrate up -m migrations
```

Runs all 11 migrations (users/orgs/devices/pairing/RLS through
`011_users_primary_organization`). Safe to re-run — it skips anything already applied.

- [ ] `Migrations complete!` printed with no errors

### 5. Start the API with your tenant wired in

Create `.env.services` at the **repository root** (already gitignored) so you don't have
to re-export these on every shell session — `npm run dev --workspace services/api` loads
it automatically (`services/api/package.json`'s `dev` script uses Node's
`--env-file-if-exists`, harmless if the file doesn't exist):

```
# .env.services — repo root
DATABASE_URL=postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow
ENTRA_TENANT_ISSUER=<issuer from step 3>
ENTRA_JWKS_URI=<jwks_uri from step 3>
ENTRA_WEB_CLIENT_ID=<client ID from step 2>
```

```bash
# services/api/
npm run dev --workspace services/api
```

Leave this running. It listens on `:8080`. If it exits immediately, one of the four env
vars above is missing or malformed — the error names the exact field. A quick way to
confirm Entra is actually wired in (not just that the process started): a bad token
should get a real rejection, not "not configured":

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/web-session/token \
  -X POST -H "Content-Type: application/json" -d '{"idToken":"not-a-real-token"}'
# 401 = Entra verifier is configured and rejected the token (correct)
# 503 = ENTRA_* isn't actually loaded — check .env.services
```

- [ ] Server logs show it listening, no startup error
- [ ] The check above returns 401, not 503

### 6. Point the Mac app at your local API

Create a file named `.env` at the **repository root** (not inside `services/`)
containing:

```
WRITERFLOW_API_BASE_URL=http://localhost:8080
```

Only DEBUG builds read this file — it's compiled out of the release DMG entirely, so
this never affects a real install.

```bash
# repo root
make run
```

- [ ] WriterFlow launches from source, menu bar icon appears

### 7. Start pairing from the Mac app

Click the WriterFlow menu bar icon → **Debug: Test Device Pairing** (only present in
this from-source build). It opens a browser tab and starts polling in the background —
ignore that tab, it's the `/pair` stub and doesn't do anything yet.

Open **Console.app**, filter for subsystem `com.karan.writerflow`, category `auth`. Find
the line `Pairing started — user_code: XXXX-XXXX` and copy that code.

The code expires (~15 minutes) if steps 8–9 take too long — if `/device/approve`
comes back `404 Unknown, expired, or already-consumed user code`, click **Debug: Test
Device Pairing** again for a fresh one rather than reusing the stale code.

- [ ] Got the `user_code` from Console.app

### 8. Sign in with Microsoft — the real thing

**This step needs PKCE.** `jwt.ms` only *decodes* a token you give it — it has no
backend, so it can't complete an authorization-code exchange. Modern Entra External ID
SPA registrations issue an authorization **code**, not an `id_token` directly, so you
need one extra manual step (exactly what the real `/pair` page will do in code once it
exists) between "sign in" and "have a token."

Generate a fresh PKCE pair — do this **once per attempt**; a `code_verifier` only
matches the `code` from the *same* authorize round trip, so don't reuse an old verifier
with a new sign-in or vice versa (that's the "code_verifier mismatch" error):

```bash
node -e "
const c = require('crypto');
const verifier = c.randomBytes(32).toString('base64url');
const challenge = c.createHash('sha256').update(verifier).digest('base64url');
console.log('code_verifier=' + verifier);
console.log('code_challenge=' + challenge);
"
```

Build the authorize URL with that `code_challenge`, your tenant subdomain, and client ID
from steps 1–2, then open it in a browser:

```
https://<tenant-subdomain>.ciamlogin.com/<tenant-subdomain>.onmicrosoft.com/oauth2/v2.0/authorize?client_id=<CLIENT_ID>&response_type=code&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid&response_mode=fragment&code_challenge=<CODE_CHALLENGE>&code_challenge_method=S256&nonce=test123
```

Sign in or sign up with any email — this is Microsoft's own hosted UI, genuinely the
same experience the real `/pair` page will eventually embed. You land on
[jwt.ms](https://jwt.ms) with an **empty body — that's expected**, it has nothing to
decode. What you need is in the address bar: `https://jwt.ms/#code=<long value>`. Copy
that `code` value immediately — it's single-use and short-lived.

- [ ] Signed in successfully, redirected to `jwt.ms/#code=...`
- [ ] Copied the `code` value from the URL

### 9. Exchange the code, then stand in for `/pair`

Three calls now — the first two are what the real sign-in page will do in code once it
exists; the third (`/device/approve`) it already does.

```bash
# exchange the authorization code for an Entra ID token — needs the SAME
# code_verifier generated in step 8, and the code before it expires (a couple minutes)
curl -s -X POST "https://<tenant-subdomain>.ciamlogin.com/<tenant-subdomain>.onmicrosoft.com/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=<CLIENT_ID>" \
  --data-urlencode "code=<code from step 8>" \
  --data-urlencode "redirect_uri=https://jwt.ms" \
  --data-urlencode "code_verifier=<code_verifier from step 8>"
```

Copy the `id_token` field from that JSON response (not `access_token` — the API verifies
the *ID* token, per V2-ARCHITECTURE.md §5.2's "immutable (issuer, subject) identity
key"). If this fails with `invalid_grant`, the code expired or was already used —
generate a fresh PKCE pair and redo step 8, don't retry with the same code.

```bash
# exchange the Entra ID token for a WriterFlow web-session token
curl -s -X POST http://localhost:8080/web-session/token \
  -H "Content-Type: application/json" \
  -d '{"idToken":"<id_token from above>"}'
```

Copy the `accessToken` from the response — that's your web-session token, valid for a
few minutes. A `401` here after the 401-vs-503 check in step 5 already passed usually
means `ENTRA_TENANT_ISSUER` or `ENTRA_WEB_CLIENT_ID` doesn't exactly match this
particular token's `iss`/`aud` claims — paste the `id_token` into
[jwt.ms](https://jwt.ms) yourself and compare its `iss`/`aud` fields character-for-character
against `.env.services`.

```bash
# approve the device
curl -s -X POST http://localhost:8080/device/approve \
  -H "Authorization: Bearer <web-session accessToken>" \
  -H "Content-Type: application/json" \
  -d '{"userCode":"<code from step 7>"}'
```

A 200 response with a full account snapshot means it worked — your user, personal
organization, and device all just got created for real.

- [ ] Token endpoint returned an `id_token`
- [ ] `/web-session/token` returned an `accessToken`
- [ ] `/device/approve` returned 200 with an account snapshot

### 10. Watch the Mac app finish pairing on its own

Within a few seconds the app's background poll picks up the approval. Console.app shows
`Pairing finished — state: signedIn(...)`. No further action needed — this is exactly
what a real user would see after finishing sign-in in a browser.

- [ ] Console.app shows `signedIn`

### 11. Check the Dashboard, then revoke

Open **Dashboard → Account**. You should see your device's label, plan, and monthly
units — pulled live from `GET /me`. Click **Revoke This Device** and confirm it signs
out and that pairing again issues a fresh device.

- [ ] Account card shows real data from the API
- [ ] Revoke signs the app out

---

## B. Optional: deploy to real Azure

Do this once Track A has convinced you the flow works. It proves the actual cloud path
(Container Apps, API Management, managed Postgres) but doesn't change what you can test
— `/pair` is still a stub, so you'll repeat the same manual exchange from Track A step
9, just pointed at the deployed API instead of `localhost`.

### 1. Know the cost before you deploy

| Resource | SKU | Approx. monthly |
|---|---|---:|
| API Management | Standard v2 | $150–200 |
| Postgres Flexible Server (dev) | Standard_B1ms, Burstable | $15–30 |
| Container Apps (API + website) | Consumption, pay-per-use | $5–20 |
| Container Registry | Standard | ~$20 |
| Key Vault + Log Analytics | Standard / pay-per-GB | a few $ |
| **Total, dev environment** | | **~$190–270/mo** |

> **Heads up.** The repo's own dev budget cap (`infra/bicep/modules/budget.bicep`) is
> set to **$100/month** — less than API Management alone. Raise
> `monthlyAmountByEnvironment.dev` before deploying, or the budget alert fires
> immediately. Also change `notificationEmail` in that same file from the placeholder
> `engineering@writerflow.aviusolutions.com` to an inbox you actually read — it isn't exposed as a
> deploy-time parameter yet.

API Management is the unavoidable cost here: the API's Container App only has private,
VNet-internal ingress by design (so nothing can reach it except through APIM) — there's
no cheaper way to make the deployed API reachable at all.

### 2. Log in and create a resource group

```bash
az login
az group create --name writerflow-dev-rg --location eastus
```

### 3. Preview, then deploy

```bash
# repo root
az deployment group what-if \
  --resource-group writerflow-dev-rg \
  --template-file infra/bicep/main.bicep \
  --parameters environmentName=dev namePrefix=wf-dev

az deployment group create \
  --resource-group writerflow-dev-rg \
  --template-file infra/bicep/main.bicep \
  --parameters environmentName=dev namePrefix=wf-dev
```

Read the `what-if` output before running `create` — it lists every resource about to be
made, so there are no surprises.

### 4. Build and push both container images

```bash
# repo root
az acr login --name <acr name from deployment output>

docker build -f services/api/Dockerfile -t writerflow-api .
docker tag writerflow-api <acr login server>/writerflow-api:latest
docker push <acr login server>/writerflow-api:latest

docker build -f website/Dockerfile -t writerflow-website .
docker tag writerflow-website <acr login server>/writerflow-website:latest
docker push <acr login server>/writerflow-website:latest
```

> **Try this locally first.** Docker Hub base-image pulls hung indefinitely in the
> sandbox this was built in — an environment issue, not a Dockerfile problem, but
> neither Docker build has been run to completion anywhere yet. Run both builds on your
> own machine before this step and confirm they finish.

### 5. Run migrations against the real database

Get the Postgres FQDN from the deployment output (`postgresFqdn`), then run the same
migration command from Track A step 4 with that host instead of `localhost`.

### 6. Repeat the manual approve, against the cloud API

Same as Track A steps 6–11, except `WRITERFLOW_API_BASE_URL` and the two `curl` targets
point at the deployed `apimGatewayUrl` output instead of `localhost:8080`, and the Entra
app registration's redirect URI / env vars can now point at whichever tenant you want to
treat as "production."

---

## What's genuinely not possible yet

- **Seeing or revoking a *different* device from the Dashboard.** `GET /me` only ever
  describes the device making the call — there's no list-devices endpoint in the API
  contract yet.
- **APIM actually enforcing token validation.** The `validate-jwt` policy is written but
  not wired to a deployed APIM instance — Section B's deployment doesn't turn this on by
  itself.
- **A real Docker build of the website image.** Written, believed correct (mirrors
  `services/api/Dockerfile`'s already-proven shape), but never actually run to completion
  in this environment (Docker Hub pulls hung) — confirm before first deploy.
- **Automated test coverage for `/pair/start` and `/pair/callback`.** Deliberately
  deferred while getting the flow working end to end manually — worth adding before
  calling this piece done, ideally with a fake/local Entra verifier seam so it doesn't
  need a live tenant to run in CI.

---

## Reference — every env var this setup touches

| Var | Set where | Value |
|---|---|---|
| `DATABASE_URL` | repo-root `.env.services` | `writerflow_app` role connection string (least-privilege runtime role) |
| `ENTRA_TENANT_ISSUER` | repo-root `.env.services` AND `website/.env.local` | `issuer` from the tenant's OpenID metadata (step 3) |
| `ENTRA_JWKS_URI` | repo-root `.env.services` | `jwks_uri` from the same metadata document |
| `ENTRA_WEB_CLIENT_ID` | repo-root `.env.services` AND `website/.env.local` | the app registration's Application (client) ID |
| `ENTRA_WEB_CLIENT_SECRET` | `website/.env.local` only | from Entra portal → Certificates & secrets → New client secret. Required for this app registration's Web platform redirect — PKCE alone got `AADSTS7000218` |
| `PAIR_REDIRECT_URI` | `website/.env.local` | `http://localhost:3000/pair/callback` — must exactly match a Web platform redirect URI registered in Entra, no trailing slash |
| `WRITERFLOW_API_BASE_URL` | `website/.env.local` (server-side call target) AND repo-root `.env` (Mac app, DEBUG builds only) | `http://localhost:8080` |

`services/api` auto-loads `.env.services` (`npm run dev`'s `--env-file-if-exists` flag);
`website` auto-loads `.env.local` (Next.js's own built-in env loading, `npm run dev`/
`npm run build` only). Both are gitignored — never commit real values.

---

Reflects the state of Phase 5, Stage 5.2 as of this session's last commit. Re-check
`phases/phase-5-v2-cloud-foundation.md` before following this if meaningful time has
passed — the exact routes/env vars may keep evolving.

# WriterFlow V2 — Setup & Testing Runbook

Phase 5 (V2 cloud foundation) only. What's actually built as of Stage 5.2, what still
needs Azure/Entra setup, and the exact steps to open the app and pair a real account
yourself — for free, today, before spending anything on cloud infrastructure.

## Status

| Piece | Status |
|---|---|
| Backend pairing + account API | Done — verified against real local Postgres |
| Mac app — pairing & Account tab | Done |
| Website `/pair` sign-in | Stub only — renders, doesn't talk to Entra yet |
| Azure infrastructure (Bicep) | Written, not deployed |
| Entra External ID tenant | Not created |

**Bottom line:** the one piece missing for a fully polished test is the website's "Sign
In" page — it renders but doesn't call Entra yet. Everything behind it (device pairing,
token issuance, your account, revoke) is real and already proven against a live
Postgres database. **Track A** below stands in for that one missing page with two
manual copy-paste steps, so you can pair a real device against a real Microsoft sign-in
today, for free. **Track B** is the optional, paid step of putting all of this on real
Azure infrastructure — do that later, once Track A convinces you the flow itself is
sound.

---

## Track A — Pair a real device, for free, on your Mac

Everything runs on your own machine: local Postgres, the API's dev server, and the Mac
app built from source. The only cloud dependency is the Entra tenant itself, which costs
nothing to create or sign into at this scale.

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
swap it for `writerflow.app/pair` once that page actually signs people in.

Add one sign-in method under **Authentication → App user flow** or **External
Identities** — email one-time passcode is the simplest to test with.

- [ ] App registered, redirect URI `https://jwt.ms` added as SPA
- [ ] Copied the **Application (client) ID** — you'll need it twice below
- [ ] At least one sign-in method (e.g. email OTP) enabled

### 3. Fetch the tenant's OpenID metadata

This gives you the exact `issuer` and `jwks_uri` values — don't guess these, a mismatch
makes token verification fail silently.

```
https://<your-tenant-subdomain>.ciamlogin.com/<your-tenant-subdomain>.onmicrosoft.com/v2.0/.well-known/openid-configuration
```

Open that URL and note two fields from the JSON: `issuer` and `jwks_uri`.

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

```bash
# services/api/
DATABASE_URL="postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow" \
ENTRA_TENANT_ISSUER="<issuer from step 3>" \
ENTRA_JWKS_URI="<jwks_uri from step 3>" \
ENTRA_WEB_CLIENT_ID="<client ID from step 2>" \
  npm run dev --workspace services/api
```

Leave this running. It listens on `:8080`. If it exits immediately, one of the four env
vars above is missing or malformed — the error names the exact field.

- [ ] Server logs show it listening, no startup error

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

- [ ] Got the `user_code` from Console.app

### 8. Sign in with Microsoft — the real thing

Build this URL with your own tenant subdomain and client ID from steps 1–2, then open it
in a browser:

```
https://<tenant-subdomain>.ciamlogin.com/<tenant-subdomain>.onmicrosoft.com/oauth2/v2.0/authorize?client_id=<CLIENT_ID>&response_type=id_token&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid&response_mode=fragment&nonce=test123
```

Sign in or sign up with any email — this is Microsoft's own hosted UI, genuinely the
same experience the real `/pair` page will eventually embed. You land on
[jwt.ms](https://jwt.ms), which decodes your token on screen. Copy the raw encoded token
(the long `eyJ...` string, shown under "Encoded" or in the address bar after
`id_token=`).

- [ ] Signed in successfully, landed on jwt.ms
- [ ] Copied the raw `id_token` value

### 9. Stand in for `/pair`: exchange and approve

These are the two calls the real sign-in page will make automatically once it's built.
Run them yourself, in order.

```bash
# exchange the Entra token for a WriterFlow web-session token
curl -s -X POST http://localhost:8080/web-session/token \
  -H "Content-Type: application/json" \
  -d '{"idToken":"<paste the id_token from step 8>"}'
```

Copy the `accessToken` from the response — that's your web-session token, valid for a
few minutes.

```bash
# approve the device
curl -s -X POST http://localhost:8080/device/approve \
  -H "Authorization: Bearer <web-session accessToken>" \
  -H "Content-Type: application/json" \
  -d '{"userCode":"<code from step 7>"}'
```

A 200 response with a full account snapshot means it worked — your user, personal
organization, and device all just got created for real.

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

## Track B — Optional: deploy to real Azure

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
> `engineering@writerflow.app` to an inbox you actually read — it isn't exposed as a
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

- **Clicking "Sign In" in the Mac app with no manual steps.** Needs `/pair`'s real Entra
  sign-in wired up — a separate, not-yet-started increment. Track A's steps 8–9 stand in
  for it by hand.
- **Seeing or revoking a *different* device from the Dashboard.** `GET /me` only ever
  describes the device making the call — there's no list-devices endpoint in the API
  contract yet.
- **APIM actually enforcing token validation.** The `validate-jwt` policy is written but
  not wired to a deployed APIM instance — Track B's deployment doesn't turn this on by
  itself.

---

## Reference — every env var Track A touches

| Var | Set where | Value |
|---|---|---|
| `DATABASE_URL` | services/api dev server | `writerflow_app` role connection string (least-privilege runtime role) |
| `ENTRA_TENANT_ISSUER` | services/api dev server | `issuer` from the tenant's OpenID metadata (step 3) |
| `ENTRA_JWKS_URI` | services/api dev server | `jwks_uri` from the same metadata document |
| `ENTRA_WEB_CLIENT_ID` | services/api dev server | the app registration's Application (client) ID |
| `WRITERFLOW_API_BASE_URL` | repo-root `.env`, DEBUG builds only | `http://localhost:8080` |

---

Reflects the state of Phase 5, Stage 5.2 as of this session's last commit. Re-check
`phases/phase-5-v2-cloud-foundation.md` before following this if meaningful time has
passed — Track A's steps depend on route shapes that are still evolving.

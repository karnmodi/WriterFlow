# WriterFlow website

Uses the Next.js App Router and Tailwind CSS. Two things live in this one app:

- The **v1 marketing site** (`/`, `/install`, `/privacy`) — still statically
  prerendered at build time, unchanged in content or behavior.
- The **v2 confidential Entra client + `/pair` device-approval route**
  (V2-ARCHITECTURE.md §5.1/§14) — a real server route, since approving a Mac
  app's pairing request needs a session and (eventually) a client secret,
  which static HTML cannot provide.

That second piece is why this app no longer builds with `output: "export"`
(Stage 5.2) — Next.js can't mix static export with a dynamic route in the same
app. `output: "standalone"` now produces a minimal self-contained Node server
(`next.config.ts`); `Dockerfile` builds it into
`infra/bicep/modules/container-app-website.bicep`'s Container App image. The
marketing pages are unaffected performance-wise — Next still statically
prerenders them at build time (see `npm run build`'s route table: `○` for
static, `ƒ` for dynamic) — this only changes how the whole app is deployed and
served.

**`/pair` and `/account` use real Entra sign-in** (Stage 5.2 / ADR-0013). The website
confidential client completes OIDC server-side, mints WriterFlow web-session or
web-account tokens, and calls `POST /v2/device/approve` — neither Entra nor
WriterFlow bearer tokens reach the browser. Membership billing UI is present but
charges remain Phase 7 (Stripe test mode only until GA).

## Local development

```bash
cd website
npm ci
npm run dev
```

The site defaults to the honest pre-release state because the manual gates in
`../RELEASE.md` are not complete. That state shows release information and the
installation guide without exposing dead download links.

## Release assets

The download URLs default to immutable GitHub Release assets:

```text
https://github.com/karnmodi/WriterFlow/releases/download/v1.0.0/WriterFlow-1.0.0.dmg
https://github.com/karnmodi/WriterFlow/releases/download/v1.0.0/WriterFlow-1.0.0.dmg.sha256
```

The version, size, platform requirements, and SHA-256 have one source of truth:
`lib/release.json`. If the final DMG changes, update that manifest before any
public build.

From the repository root, create and verify the final local artifacts, then
cross-check them against the website manifest:

```bash
make verify-release
npm --prefix website ci
npm --prefix website run verify-release-local
```

Upload those exact two files to the `v1.0.0` GitHub Release. After the release
is public, verify both unauthenticated URLs and recompute the downloaded DMG
hash:

```bash
npm --prefix website run verify-release-live
```

The public-download build is allowed only after every manual gate in
`../RELEASE.md` passes and both asset checks above succeed:

```bash
cd website
NEXT_PUBLIC_RELEASE_STATUS=available npm run check
```

The release status is baked into the HTML at build time; setting it only in a
runtime host environment does nothing. Keep it at `candidate` for previews.

To host the immutable files on the same static origin instead, set
`NEXT_PUBLIC_RELEASE_ASSET_BASE_URL` to a root-relative directory such as
`/downloads/v1.0.0`. Set `NEXT_PUBLIC_SITE_ORIGIN` when running the live asset
verifier. These are public locations, never credentials. Absolute asset
overrides must be credential-free HTTPS URLs.

## Deployment

Build and run the container the same way `infra/bicep/modules/
container-app-website.bicep` deploys it, from the repository root (the
Dockerfile needs the monorepo root as build context to resolve
`website/package-lock.json` against the workspace):

```bash
docker build -f website/Dockerfile -t writerflow-website .
docker run -p 3000:3000 writerflow-website
```

Set `NEXT_PUBLIC_RELEASE_STATUS=available` in the **build** step (it's baked
into the static HTML at build time — setting it only at runtime does
nothing), only after every manual gate in `../RELEASE.md` passes and both
release-asset checks above succeed.

**Status: code complete; cloud apply pending.** No real Container App has
been deployed yet — see `infra/bicep/main.bicep`'s `websiteApp` module and the
phase-5 notes on why the website needs its own public Container Apps
environment (`infra/bicep/modules/container-app-website.bicep`'s header
comment), separate from the API's internal-only one.

After a real deployment, test from an unauthenticated browser and from the
command line:

```bash
curl -I https://YOUR-SITE.example/
curl -I https://YOUR-SITE.example/install/
curl -I https://YOUR-SITE.example/privacy/
curl -I https://YOUR-SITE.example/api/health/
npm run verify-release-live
```

Download both release files from the deployed page and run the Install page's
`shasum -a 256 -c` command once more. Check the mobile layout, keyboard focus,
and reduced-motion setting in a clean browser profile.

## Validation

```bash
npm run lint
npm run typecheck
npm run build
npm run validate-build
```

`npm run check` runs all four. The build validator checks the Home, Install,
Privacy, and 404 pages are still statically prerendered, that `/pair` is
*not* accidentally prerendered (it must stay dynamic), required trust
disclosures, release-link state, and that the standalone server the
Dockerfile deploys actually got produced. `verify-release-local` and
`verify-release-live` perform the artifact checks that an HTML validator
cannot.

The marketing pages still ship no analytics on `/`, `/install`, or `/privacy`.
Account and pairing routes set httpOnly session cookies (`wf_web_account`,
`wf_entra_id_token_hint`, `wf_pair_pkce`) — see ADR-0013.

## Entra sign-in (local)

Required in `website/.env.local` (see `.env.services` for API-side Entra vars):

```bash
ENTRA_TENANT_ISSUER=https://<tenant>.ciamlogin.com/<tenant-id>/v2.0
ENTRA_WEB_CLIENT_ID=<app-registration-client-id>
ENTRA_WEB_CLIENT_SECRET=<client-secret>   # required for this tenant
PAIR_REDIRECT_URI=http://localhost:3000/pair/callback
AUTH_REDIRECT_URI=http://localhost:3000/auth/callback   # optional; defaults from PAIR_REDIRECT_URI
WRITERFLOW_API_BASE_URL=http://localhost:8080
NEXT_PUBLIC_SITE_ORIGIN=http://localhost:3000             # used for post-logout redirect
```

Register **both** redirect URIs and a **logout redirect URI**
(`http://localhost:3000/account?signedOut=1`) on the Entra app registration.

Routes:

| Path | Purpose |
|---|---|
| `/account` | Signed-in account home (or Sign in CTA) |
| `/auth/start` | Begin Microsoft sign-in |
| `/auth/callback` | Complete sign-in; sets `wf_web_account` cookie |
| `/auth/sign-out` | Clear cookies + Entra `end_session` logout |
| `/pair` | Device pairing (reuses web session when present) |

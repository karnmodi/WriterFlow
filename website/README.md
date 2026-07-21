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

**`/pair` is a stub today.** It renders the page and reads the Mac app's
`user_code`, but does not yet sign anyone in or call `POST /v2/device/approve`
— that needs a real Entra External ID tenant (not created yet) and an OIDC
client library decision, which is deliberately a separate increment. Building
a page that *looked* functional before there was a tenant to sign in against
would be actively misleading.

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

The marketing pages still ship no analytics, forms, cookies, or runtime
fetches. `/pair` is the one deliberate exception to "no backend routes" — it
will need a session cookie once Entra sign-in is wired up; that scope stays
confined to `/pair` and its supporting API routes, not the marketing pages.

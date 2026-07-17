# WriterFlow launch website

Static public launch site for WriterFlow 1.0. It uses the Next.js App Router,
Tailwind CSS, and `output: "export"`; the production artifact is the `out/`
directory and needs only a static file host. There are no runtime server routes.

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

## Static deployment

Deploy the **contents** of `website/out/` as the document root of the production
origin. This source tree deliberately does not select a hosting vendor or add a
mutable deployment backend. Because routes and Next assets are root-relative,
project-subpath hosting (for example, `example.com/project/`) is not supported
without adding and testing a matching Next `basePath`; use an origin root or a
custom domain.

Set `NEXT_PUBLIC_RELEASE_STATUS=available` in the build job, not in the runtime
serving layer. The build job should run `npm ci` and `npm run check`, then upload
only `out/` to the host's static document root.

After deployment, test from an unauthenticated browser and from the command
line:

```bash
curl -I https://YOUR-SITE.example/
curl -I https://YOUR-SITE.example/install/
curl -I https://YOUR-SITE.example/privacy/
npm run verify-release-live
```

Download both release files from the deployed page and run the Install page's
`shasum -a 256 -c` command once more. Check the mobile layout, keyboard focus,
and reduced-motion setting in a clean browser profile.

Rollback is static: redeploy the last known-good `out/`. If the release assets
are wrong or unavailable, rebuild with `NEXT_PUBLIC_RELEASE_STATUS=candidate`
and deploy that output to remove the download actions while preserving the
installation and status pages.

## Validation

```bash
npm run lint
npm run typecheck
npm run build
npm run validate-export
```

`npm run check` runs all four. The export validator checks the Home, Install,
Privacy, and 404 pages, required trust disclosures, release-link state, and the
absence of an API output. `verify-release-local` and `verify-release-live`
perform the artifact checks that a static HTML validator cannot.

No analytics, forms, cookies, backend routes, custom APIs, runtime fetches, or
server actions are included.

# WriterFlow v1.0 production and release plan

This document is the canonical production path for v1.0. It supersedes older notes
that treated Developer ID signing, notarization, or Sparkle as v1 release blockers.

## Decision summary

| Area | v1.0 now | v2.0 later |
|---|---|---|
| Availability | Public download is free; core AI actions require the user’s own Azure OpenAI key (bring-your-own-key). No WriterFlow account, membership, or subscription | Optional commercial, membership, team, or licensing model; optional provider-managed zero-key transport |
| User data | Existing local GRDB/SQLite and UserDefaults storage only; no remote user/account/membership database; user key lives only in that user’s Keychain | Any remote user, membership, entitlement, billing, or sync database |
| AI processing | Direct Azure OpenAI Responses API with the user’s endpoint + key + deployment names (configured in Setup / Settings) | A provider-managed no-key transport, or a bespoke WriterFlow relay only if the no-custom-API policy is explicitly changed |
| App-facing APIs | No bespoke WriterFlow HTTP, REST, or GraphQL API | Still disallowed unless the product policy changes |
| Distribution | Release build, verified hardened-runtime ad-hoc app signature (or an explicit reviewed security exception), public DMG, SHA-256 checksum, manual Gatekeeper approval, manual updates | Apple Developer Program, Developer ID trust, notarization, stapling, and Sparkle |

For this plan, **no custom APIs** means WriterFlow does not create or operate an
app-facing service endpoint. Calling Azure OpenAI with the user’s own credentials is
allowed. Hosting static release files, checksums, documentation, or a non-secret
static configuration file is not an API.

**Product policy (explicit):** v1.0 is **bring-your-own-key (BYO)**. The app download
is free; AI usage bills the user’s Azure account. Public copy must say this honestly.
A future provider-managed transport with no user key remains a v2 option, not a v1
blocker.

## AI security boundary

The public app must never contain, download, or persist a **publisher-owned/shared**
Azure, OpenAI, or other provider API key or reusable service credential. Putting one
in the binary, resources, UserDefaults, Keychain, `.env`, `secrets.env`, or an
obfuscated value still releases it to a user who controls the Mac.

Allowed for BYO v1:

- the **user** pastes their own Azure OpenAI API key in Setup / Settings;
- that key is stored only in the **user’s** macOS Keychain (never in the DMG/app bundle);
- the user configures their own Responses endpoint and deployment names in `models.json`
  via the UI (Application Support, local only);
- local developer `.env` / `secrets.env` bootstrap remains for contributors only and
  must never be packaged into a public artifact.

Not allowed:

- shipping or downloading a WriterFlow-funded or shared service key;
- treating Usage-tab cost figures as WriterFlow billing (they are estimates of the
  user’s own Azure spend).

Do not ship a publisher-funded key in the desktop app as a temporary workaround.

## v1.0 production gates

The following are required before publishing the DMG. They are implementation and
verification work; documenting them here does not claim they are already complete.

- [x] Adopt BYO Azure OpenAI as the public v1 AI path (Setup + Settings endpoint/key/
  deployment UI; Keychain for the user key; no shared credential in the artifact).
- [ ] Ensure text leaves the Mac only after an explicit user action. The current
  background recommendation classifier reads and sends field text while the user is
  typing, so it must be removed, replaced by a deterministic non-AI local heuristic,
  or moved behind an explicit action.
- [x] Public path uses Keychain for the user key; `.env` / `secrets.env` bootstrap is
  local-dev only and must not appear in the DMG. Endpoint + deployments are
  user-configured (not a publisher shared key).
- [x] Usage pricing editor is labeled as the user’s own Azure cost estimate — WriterFlow
  never bills the user.
- [ ] Require HTTPS (and preferably an Azure OpenAI host allowlist) before attaching any
  credential or user text; remove unneeded App Transport Security exceptions and
  sanitize upstream error bodies before display or logging.
- [ ] Confirm the public app and DMG contain no `.env`, `secrets.env`, API key, bearer
  token, signing credential, or private endpoint.
- [ ] Disable/omit `RemoteConfigFetcher` from the public build unless its sole input is
  a disclosed static non-secret artifact fetched over allowlisted HTTPS with strict
  schema and integrity/signature validation. Its current arbitrary URL + unsigned JSON
  behavior is not production-approved (leave the optional Settings field blank by default).
- [ ] Keep GRDB history, memory, snippets, and app rules local. Add no remote user,
  membership, entitlement, billing, or sync database.
- [ ] Set `CFBundleShortVersionString` to `1.0.0`, synchronize every version source,
  and decide the supported CPU architecture. The current artifact is ARM64-only, so
  do not advertise Intel support unless a universal build is produced and tested.
- [ ] Make ad-hoc signing fail the release on error and enable hardened runtime after
  verifying every required Accessibility/Input Monitoring workflow. Hardened runtime
  itself needs no Apple membership and is the v1 default. If compatibility genuinely
  fails, shipping without it requires an explicit documented security exception; the
  script must never fall back silently.
- [ ] Complete the live UI/Accessibility checks and the eight-hour CPU/memory soak.
- [ ] Load/cost-test the actual request pattern. The current multi-variant path can
  make three provider calls for one action; decide whether v1 keeps that behavior and
  document that cost hits the user’s Azure quota.
- [ ] Add required third-party license notices to the distributed artifact.
- [ ] Test the exact unidentified-developer install flow on a clean, unmanaged Mac
  (including BYO key entry in Setup with no local `.env`).
- [ ] Remove automatic quarantine-clearing from `AppRelocator`; it cannot run before
  Gatekeeper approval and must not be presented as a substitute for Apple's supported
  **Open Anyway** flow.

## Build and package v1.0

No Apple Developer Program membership or Apple signing credential is required for this
path. Run it only after all production gates above pass:

```bash
make clean
CONFIG=release make bundle
make dmg
(cd build && shasum -a 256 WriterFlow-1.0.0.dmg > WriterFlow-1.0.0.dmg.sha256)
```

The current `scripts/bundle.sh` attempts an ad-hoc signature but suppresses signing
failure and does not enable hardened runtime. The current
`scripts/make-dmg.sh` packages `build/WriterFlow.app`; it does not prove that the app
is fresh, Release-configured, version 1.0.0, secret-free, or universal. Those checks
must be automated in the next production-hardening step before this becomes a
single-command release workflow.

Before upload:

1. Inspect the bundle identity, version, architectures, signature, and DMG structure:

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/WriterFlow.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/WriterFlow.app/Contents/Info.plist
   lipo -archs build/WriterFlow.app/Contents/MacOS/WriterFlow
   codesign --verify --deep --strict --verbose=2 build/WriterFlow.app
   codesign -dv --verbose=4 build/WriterFlow.app 2>&1
   hdiutil verify build/WriterFlow-1.0.0.dmg
   ```

   Confirm the expected bundle ID/version/architectures, `Signature=adhoc`, and—after
   that v1 hardening is implemented—the runtime flag. `spctl --assess` rejection is
   expected for this unidentified v1 and is not a failed packaging check.
2. Mount the DMG and repeat the credential, private-endpoint, and third-party-notice
   review against its contents. A filename search is useful but cannot prove an
   unknown secret is absent; the forthcoming release verifier must combine artifact
   scanning with a review of every build input and generated resource.
3. Verify the SHA-256 file from the directory whose filenames it records:

   ```bash
   (cd build && shasum -a 256 -c WriterFlow-1.0.0.dmg.sha256)
   ```

4. Upload a release candidate, then download it through the intended public HTTPS URL
   in a normal browser before testing Gatekeeper. A local/USB copy may lack quarantine
   metadata and produce a false pass.
5. Install and exercise onboarding, explicit-action AI processing, Replace, launch at
   login, diagnostics export, and app relaunch on a clean Mac.
6. Publish the DMG, checksum, release notes, privacy disclosure, and exact supported
   macOS/CPU requirements together.

SHA-256 proves that a download matches the published value; it does not establish the
publisher's identity. Serve both from the authenticated project release page/HTTPS
origin and do not describe the checksum as a replacement for Developer ID trust.

Do not run `make release` / `scripts/release.sh` for v1. Those commands are the
deferred Developer ID and notarization workflow and intentionally require Apple
credentials.

## v1.0 user installation and updates

Because the app inside the v1 DMG is ad-hoc signed and not notarized, normal first
launch is blocked by Gatekeeper. The supported user flow is:

1. Download the DMG and `.sha256` file from the official release page into the same
   directory, then verify it. For the usual Downloads folder:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c WriterFlow-1.0.0.dmg.sha256
   ```

2. Drag WriterFlow to Applications before opening it.
3. Try to open WriterFlow once and dismiss the unidentified-developer warning.
4. Open **System Settings → Privacy & Security**, scroll to Security, and click
   **Open Anyway** for WriterFlow; confirm **Open** in the next prompt.
5. Grant Accessibility and Input Monitoring only after the app opens.

Do not tell users to disable Gatekeeper or run `xattr` commands. Organization-managed
Macs may prohibit the override, so this v1 is publicly downloadable but cannot be
promised to install on every managed Mac. Ad-hoc identity can also change between
builds, so a manual update may require Accessibility/Input Monitoring approval again.

## Deferred to v2.0

None of the following blocks the v1.0 tag under the current plan:

- paid Apple Developer Program membership;
- Developer ID Application signing and trusted Gatekeeper identity;
- notarization submission, ticket stapling, and Developer ID-signed DMGs;
- Sparkle, an appcast, EdDSA update signing, and automatic updates;
- remote accounts, user profiles, membership/entitlement storage, billing,
  subscriptions, licensing, teams, or cross-device sync;
- a new bespoke WriterFlow relay/API, unless “no custom APIs” is deliberately reversed.
  An existing managed transport on WriterFlow infrastructure may qualify under the v1
  criteria described above without becoming this deferred work.

The existing `scripts/release.sh` and `WriterFlow.entitlements` are retained only as
v2 scaffolding. They are not the current production path.

## Authoritative references

- [Apple: safely open an app from an unidentified developer](https://support.apple.com/en-us/102445)
- [Apple: signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [OpenAI: API key safety](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety)
- [Microsoft: keyless Azure OpenAI connections](https://learn.microsoft.com/en-us/azure/developer/ai/keyless-connections) — research reference only; its Entra ID/RBAC requirements do not establish a free anonymous public-client solution for WriterFlow.

# WriterFlow v1.0 production and release plan

This document is the canonical production path for v1.0. It supersedes older notes
that treated Developer ID signing, notarization, or Sparkle as v1 release blockers.

## Decision summary


| Area            | v1.0 now                                                                                                                                                                             | v2.0 later                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Availability    | Public download is free; core AI actions require the user’s own Azure OpenAI key (bring-your-own-key). No WriterFlow account, membership, or subscription                            | Optional commercial, membership, team, or licensing model; optional provider-managed zero-key transport                   |
| User data       | Existing local GRDB/SQLite and UserDefaults storage only; no remote user/account/membership database; user key lives only in that user’s Keychain                                    | Any remote user, membership, entitlement, billing, or sync database                                                       |
| AI processing   | Direct Azure OpenAI Responses API with the user’s endpoint + key + deployment names (configured in Setup / Settings)                                                                 | A provider-managed no-key transport, or a bespoke WriterFlow relay only if the no-custom-API policy is explicitly changed |
| App-facing APIs | No bespoke WriterFlow HTTP, REST, or GraphQL API                                                                                                                                     | Still disallowed unless the product policy changes                                                                        |
| Distribution    | Release build, verified hardened-runtime ad-hoc app signature (or an explicit reviewed security exception), public DMG, SHA-256 checksum, manual Gatekeeper approval, manual updates | Apple Developer Program, Developer ID trust, notarization, stapling, and Sparkle                                          |


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
- [x] Ensure text leaves the Mac only after an explicit user action. Passive typing now
  drives local icon state only; recommendation classification starts only after the
  user explicitly opens the action menu.
- [x] Public path uses Keychain for the user key; `.env` / `secrets.env` bootstrap is
  local-dev only and must not appear in the DMG. Endpoint + deployments are
  user-configured (not a publisher shared key).
- [x] Usage pricing editor is labeled as the user’s own Azure cost estimate — WriterFlow
  never bills the user.
- [x] Require HTTPS and an Azure host allowlist before attaching any credential or user
  text; only `/openai/responses` URLs on `*.openai.azure.com` or
  `*.cognitiveservices.azure.com` with an `api-version` are accepted. Unneeded ATS
  exceptions were removed and upstream error bodies are neither displayed nor logged.
- [x] Confirm the public app and mounted DMG contain no `.env`, `secrets.env`, API key,
  bearer token, signing credential, or private endpoint. `make verify-release` scans
  forbidden filenames, common secret patterns, and exact nonempty local `.env`
  credential/endpoint values without printing them.
- [x] Remove `RemoteConfigFetcher` and its arbitrary URL Settings surface from public v1.
- [x] Keep GRDB history, memory, snippets, and app rules local. Add no remote user,
  membership, entitlement, billing, or sync database.
- [x] Set `CFBundleShortVersionString` / Xcode marketing version to `1.0.0`. V1 supports
  **Apple Silicon (ARM64) only**; the release verifier rejects any other slice and
  public copy states that Intel is unsupported.
- [x] Make ad-hoc release signing fail on error and enable/verify hardened runtime.
  Debug signing remains lenient for contributor rebuilds; the public workflow is strict.
- [ ] Complete the live UI/Accessibility checks and the eight-hour CPU/memory soak.
- [x] Decide the v1 request/cost pattern: one provider request per explicit writing
  action (parallel three-variant generation is disabled). Usage/cost is charged against
  the user's own Azure quota and labeled as an estimate; unit tests lock this policy.
- [x] Add the GRDB MIT notice to `THIRD-PARTY-NOTICES.txt` and verify it is bundled.
- [ ] Test the exact unidentified-developer install flow on a clean, unmanaged Mac
  (including BYO key entry in Setup with no local `.env`).
- [x] Remove automatic quarantine-clearing from `AppRelocator`; installation docs use
  Apple's supported **Open Anyway** flow only.

## Manual evidence still required before public upload/tag

These checks cannot be proven by compilation or an artifact scanner. Record the tester,
date, Mac model/macOS version, and result in the release notes before changing them:

- [ ] Live Accessibility/Input Monitoring matrix: onboarding, icon/hotkey, action menu,
  streaming preview, Replace/Copy/Retry/Discard, clipboard fallback, launch at login,
  diagnostics export, relaunch, fullscreen, Spaces, and an external display.
- [ ] Eight-hour normal-use soak with measured idle CPU `<1%` and RSS `<80 MB`, with no
  event-tap/AX degradation.
- [ ] Clean, unmanaged Apple Silicon Mac with no developer tools and no local `.env`:
  browser-download the release candidate, verify SHA-256, drag to Applications, complete
  **Open Anyway**, grant permissions, configure BYO Azure, and complete a first rewrite.
- [ ] Download the final uploaded DMG + checksum back from the public HTTPS release page
  and repeat checksum verification (a local copy does not exercise quarantine).

Do not create the `v1.0.0` tag or describe the build as generally released until all
four boxes have evidence.



## Build and package v1.0

No Apple Developer Program membership or Apple signing credential is required for this
path. Run it only after all production gates above pass:

```bash
make verify-release
```

`scripts/release-v1.sh` cleans previous output, runs unit tests, builds Release,
requires hardened-runtime ad-hoc signing, verifies bundle ID/version/ARM64 architecture,
bundles third-party notices, scans the app and mounted DMG for credentials/private
endpoints, verifies DMG integrity, and creates + verifies the SHA-256 file. Any failed
check stops the workflow.

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

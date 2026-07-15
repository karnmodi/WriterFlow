# WriterFlow

Native macOS menu-bar writing assistant. While you type in any app (Gmail, WhatsApp, Slack, Notes, …), a small floating icon appears. Click it — or press **⌃⌥ Space** — to rewrite, reply, or follow a custom instruction in place. Think Whisperflow, but for typing instead of voice.

Requires **macOS 14+**. Not distributed via the Mac App Store (Accessibility APIs used here fail App Store review).

---

## How it works

```
You type in another app
        ↓
FocusMonitor (Accessibility + Input Monitoring)
  · detects a focused text field (skips password / secure fields)
  · shows a non-activating floating icon near the field
        ↓
You pick an action (popover or hotkey)
  Elaborate · Formal · Casual · Fix Grammar · Reply · Prompt Builder · Custom
        ↓
ActionEngine
  · reads field text (+ conversation context for Reply / Custom / Prompt Builder)
  · streams Azure OpenAI Responses API (SSE)
  · shows result in a preview card
        ↓
You Replace / Copy / Retry / Discard
  · primary path: Accessibility write back into the field
  · fallback: clipboard paste if AX write fails
```

**Privacy notes**

- Text is sent to Azure OpenAI **only when you pick an action** — never while idle or while typing.
- Input Monitoring is used only as a local “you are typing” signal. Key contents are never buffered, logged, or sent.
- Secure fields (`AXSecureTextField` / secure input) make WriterFlow completely inert — no icon, no reads.
- Overlay panels are **non-activating**: keyboard focus stays in the app you are typing in.

**Architecture (source layout)**

| Folder | Role |
|---|---|
| `Sources/WriterFlow/App/` | Menu bar, onboarding, settings, hotkey |
| `Sources/WriterFlow/FocusMonitor/` | AX focus + typing detection, app adapters |
| `Sources/WriterFlow/Overlay/` | Floating icon, action popover, preview card, toasts |
| `Sources/WriterFlow/Engine/` | Azure client, prompts, replace / clipboard pipeline |
| `Sources/WriterFlow/Store/` | Settings, Keychain, `.env` / `models.json` |

Planning docs: `PRD.md`, `ROADMAP.md`, `phases/`, `CLAUDE.md`.

---

## New Mac setup

### 1. System requirements

- macOS **14 Sonoma** or newer
- Apple Silicon or Intel Mac
- Network access to your Azure OpenAI endpoint

### 2. Install toolchain

Command Line Tools are enough (full Xcode is optional):

```bash
xcode-select --install
```

Optional:

```bash
# Homebrew (if you don't have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install swiftlint   # only needed for `make lint`
```

Confirm Swift works:

```bash
swift --version   # 5.9+ expected with recent CLT
```

### 3. Clone the repo

```bash
git clone <your-repo-url> WriterFlow
cd WriterFlow
```

### 4. Create `.env` (Azure credentials)

`.env` is **gitignored**. On a new machine, create one from the template:

```bash
cp .env.example .env
```

Edit `.env` and set at least:

| Variable | Purpose |
|---|---|
| `TARGET_URI` | Full Azure OpenAI **Responses** API URL, including `api-version` |
| `API_KEY_GPT_5-4_Pro` | API key (bootstrapped into Keychain on first launch) |
| `AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini` | Default / grammar deployment name |
| `AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro` | Heavy / Pro deployment name |

Example shape (replace with your real resource):

```bash
TARGET_URI=https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview
API_KEY_GPT_5-4_Pro=your-key-here
AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini=gpt-5.4-mini
AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro=gpt-5.4-pro
```

**Smoke-test the endpoint** (optional but recommended before launching the app):

```bash
chmod +x scripts/test-azure.sh
./scripts/test-azure.sh
# expect: OK: <some streamed text>
```

You can also paste/validate a key later from **WriterFlow → Settings** (stored in Keychain only).

### 5. Build and install

Prefer the **stable install path** so Accessibility / Input Monitoring permissions survive rebuilds:

```bash
make install-run
```

That builds the app, copies it to `~/Applications/WriterFlow.app`, syncs credentials into Application Support, stops any old instance, and launches.

Other useful commands:

| Command | What it does |
|---|---|
| `make build` | `swift build` only |
| `make test` | Unit tests |
| `make bundle` | Build → `build/WriterFlow.app` |
| `make run` | Bundle + launch from `build/` (permissions may break after rebuilds) |
| `make install` | Install to `~/Applications` without launching |
| `make stop` | Quit running WriterFlow |
| `make clean` | Remove `.build` and `build/` |

### 6. Grant macOS permissions (one-time)

On first launch a setup window appears. Grant both:

1. **System Settings → Privacy & Security → Accessibility**  
   Enable **WriterFlow**. Prefer adding `~/Applications/WriterFlow.app`.
2. **System Settings → Privacy & Security → Input Monitoring**  
   Enable **WriterFlow** (same app path).

If the toggles look ON but onboarding still complains (common after rebuilding a different path):

- Remove old WriterFlow entries (−), then **+** and re-add `~/Applications/WriterFlow.app`
- Or use **Repair Accessibility** in the setup window
- Quit and reopen WriterFlow

Look for the **WF** glyph in the menu bar (top-right). There is no Dock icon (`LSUIElement`).

### 7. First use check

1. Open Notes (or Gmail / Slack).
2. Type a sentence in a normal text field (not a password field).
3. A floating wave icon should appear near the field.
4. Click it, or press **⌃⌥ Space**, pick **Casual** / **Fix Grammar**, wait for the streamed preview, press **Enter** to Replace.

---

## Runtime data (per Mac)

Created automatically; none of this is in git:

| Path | Contents |
|---|---|
| `~/Applications/WriterFlow.app` | Installed app (stable TCC identity) |
| `~/Library/Application Support/WriterFlow/models.json` | Deployment routing (bootstrapped from `.env`) |
| `~/Library/Application Support/WriterFlow/secrets.env` | Synced non-Keychain credential fallback |
| `~/Library/Application Support/WriterFlow/compatibility.json` | Per-app AX / context diagnostics |
| Keychain | API key (`KeychainStore`) |

To start clean on a machine: quit WriterFlow, delete the Application Support folder above, and remove Keychain items for WriterFlow if you want a full reset.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No floating icon | Check Accessibility is ON for `~/Applications/WriterFlow.app`; ensure the field isn’t secure; app not paused from the menu bar |
| Hotkey does nothing | Confirm **⌃⌥ Space** (Control + Option + Space); check Input Monitoring is ON |
| “Nothing to rewrite” | Type or select text first (Reply can run on empty field using conversation context) |
| Azure / stream errors | Re-check `TARGET_URI` + deployment names; run `./scripts/test-azure.sh`; or paste a new key in Settings |
| Permissions break after `make run` / clean build | Use `make install-run` and re-pair Accessibility to `~/Applications/WriterFlow.app` |
| Build fails | `xcode-select -p` should point at CLT or Xcode; `swift --version` ≥ 5.9; macOS 14 SDK |

---

## Developing

```bash
make test
make lint          # requires swiftlint
make install-run   # preferred daily loop
```

Open `Package.swift` in Xcode if you have it installed — full Xcode is not required for build/run.

Phase checklists live under `phases/`. Product requirements: `PRD.md`. Changes so far: `CHANGELOG.md`.

---

## Releasing

WriterFlow ships as a notarized Developer ID app (no Mac App Store — the Accessibility
APIs it depends on would fail App Store review).

1. **Sign + notarize**: `make release` (wraps `scripts/release.sh`). Requires a paid
   Apple Developer Program membership and these environment variables:

   | Variable | Where to get it |
   |---|---|
   | `DEVELOPER_ID_APPLICATION` | Your `"Developer ID Application: Name (TEAMID)"` signing identity, e.g. from `security find-identity -v -p codesigning` |
   | `APPLE_ID` | The Apple ID enrolled in the Developer Program |
   | `APPLE_TEAM_ID` | 10-character Team ID (developer.apple.com → Membership) |
   | `APPLE_APP_SPECIFIC_PASSWORD` | Generate at appleid.apple.com → Sign-In and Security → App-Specific Passwords |

   The script fails fast with a clear message if any of these are missing — it never
   silently skips signing or notarization. `WriterFlow.entitlements` (hardened runtime +
   `com.apple.security.network.client`, the only capability needed since the app is
   unsandboxed) is applied during signing.

2. **Package**: `make dmg` (wraps `scripts/make-dmg.sh`) builds a drag-to-Applications
   DMG from `build/WriterFlow.app` — an `Applications` symlink alongside the app, the
   standard macOS install pattern. Run this after `make release` for a distributable
   build, or straight after `make bundle` for a local-only test DMG (Gatekeeper will
   still refuse an ad-hoc-signed build on another Mac).

3. **First launch off a DMG**: if a user opens WriterFlow straight from the mounted
   image instead of dragging it to Applications, `AppRelocator` detects the `/Volumes/`
   path and offers to copy itself to `~/Applications` (clearing the inherited quarantine
   flag) and relaunch from there.

**Not yet wired up: Sparkle 2 auto-updates.** This needs a publicly hosted appcast
(GitHub Pages/S3) and a generated EdDSA signing key before there's anything useful to
integrate against — adding the Sparkle dependency now, pointed at a feed that doesn't
exist, would be a checkbox that quietly does nothing. Get the appcast hosting decided
first, then wire `SPUStandardUpdaterController` + an `SUFeedURL` in Info.plist.

**Diagnostics, not automated crash reporting.** Settings → Reliability → "Share
Diagnostics" writes a local text file (app/OS version, per-app AX success/fail counts,
recent crash reports macOS already collected under `~/Library/Logs/DiagnosticReports/`)
that the user explicitly saves and can choose to send — nothing is ever collected or
uploaded automatically.

**Versioning**: no `v1.0.0` tag exists yet. Cut one once a signed+notarized build has
actually been through Phase 4's exit criteria and Phase 3's live-verification pass — see
`CLAUDE.md`'s current-state note for what's still pending.

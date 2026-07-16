# WriterFlow

Native macOS menu-bar writing assistant. While you type in any app (Gmail, WhatsApp, Slack, Notes, …), a small floating icon appears. Click it — or press **⌃⌥ Space** — to rewrite, reply, or follow a custom instruction in place. Think Whisperflow, but for typing instead of voice.

Requires **macOS 14+**. Not distributed via the Mac App Store (Accessibility APIs used here fail App Store review). The current development artifact is ARM64-only; do not claim Intel support until a universal build is produced and tested.

The v1 goal is a public, free download (**bring-your-own-key**): AI actions use the user’s Azure OpenAI endpoint and API key. No WriterFlow account, membership, or shared publisher key. See [`RELEASE.md`](RELEASE.md) for production/security gates and the v1/v2 split.

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
  · streams through the user’s Azure OpenAI resource (BYO key + endpoint)
  · shows result in a preview card
        ↓
You Replace / Copy / Retry / Discard
  · primary path: Accessibility write back into the field
  · fallback: clipboard paste if AX write fails
```

**Privacy notes**

- Production rule: text may leave the Mac **only when you pick an action** — never while idle or while typing. The payload may include selected/field text, visible conversation context, a custom instruction, and enabled local personalization. The explicit **Analyze My Writing Style** action may send up to 20 accepted outputs for that one analysis.
- Input Monitoring is used only as a local “you are typing” signal. Key contents are never buffered, logged, or sent.
- Secure fields (`AXSecureTextField` / secure input) make WriterFlow completely inert — no icon, no reads.
- Overlay panels are **non-activating**: keyboard focus stays in the app you are typing in.
- If a field's contents can't be read directly (some Electron/web fields), WriterFlow falls back to a brief select-all-and-copy — still only as part of an action you explicitly triggered — and restores your prior selection and clipboard contents immediately afterward.
- A handful of password managers are excluded by default (no icon, no reads at all); add any other app the same way from **Dashboard → Personalization**.
- V1 keeps history, memory, snippets, and app rules in local GRDB/SQLite only. There is no remote user, membership, entitlement, billing, or sync database and no custom WriterFlow API.
- A public build must contain no maintainer-owned provider key, `.env`, `secrets.env`, bearer token, private endpoint, or signing credential. Each user pastes **their own** key in Setup / Settings; it stays in that user’s Keychain only.

**Production status:** BYO Azure is the approved public AI path (Setup + Settings). Remaining release blockers in [`RELEASE.md`](RELEASE.md) include the Recommendation Engine still sending field text while typing, DMG secret-scanning / Gatekeeper soak, and related packaging gates — do not tag `v1.0.0` until those pass.

**Architecture (source layout)**

| Folder | Role |
|---|---|
| `Sources/WriterFlow/App/` | Menu bar, onboarding (permissions + BYO Azure), settings, hotkey |
| `Sources/WriterFlow/FocusMonitor/` | AX focus + typing detection, app adapters |
| `Sources/WriterFlow/Overlay/` | Floating icon, action popover, preview card, toasts |
| `Sources/WriterFlow/Engine/` | Azure OpenAI client, prompts, replace / clipboard pipeline |
| `Sources/WriterFlow/Store/` | Local settings/data; user Keychain key + `models.json` endpoint/deployments |

Planning docs: `PRD.md`, `ROADMAP.md`, `RELEASE.md`, `phases/`, plus mirrored `CLAUDE.md` / `AGENTS.md` tool context.

---

## Local development setup

This section is for contributors running the current direct Azure development transport. It is **not** the public v1 install flow and its credentials must never be copied into a release artifact.

### 1. System requirements

- macOS **14 Sonoma** or newer
- Apple Silicon Mac for the currently verified build (Intel/universal output is a production decision still to be completed)
- Network access to a developer-owned Azure OpenAI endpoint

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

### 4. Create `.env` (development credentials only)

`.env` is **gitignored** and is only for local development. On a new contributor machine, create one from the template:

```bash
cp .env.example .env
```

Edit `.env` and set at least:

| Variable | Purpose |
|---|---|
| `TARGET_URI` | Full Azure OpenAI **Responses** API URL, including `api-version` |
| `API_KEY_GPT_5-4_Pro` | Developer-owned API key used by the current local transport; never for a public artifact |
| `AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini` | Default / grammar deployment name |
| `AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro` | Heavy / Pro deployment name |

Example shape (replace with your real resource):

```bash
TARGET_URI=https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview
API_KEY_GPT_5-4_Pro=your-key-here
AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini=gpt-5.4-mini
AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro=gpt-5.4-pro
```

**Smoke-test the development endpoint** (optional but recommended before launching the app):

```bash
chmod +x scripts/test-azure.sh
./scripts/test-azure.sh
# expect: OK: <some streamed text>
```

The current development UI can also paste/validate a user-owned key. Do not use this path to distribute a maintainer/shared key; the production transport and UI must not expose one.

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
| `~/Library/Application Support/WriterFlow/secrets.env` | Current development-only plaintext credential fallback; prohibited in public v1 and scheduled for removal/gating |
| `~/Library/Application Support/WriterFlow/compatibility.json` | Per-app AX / context diagnostics |
| Keychain | Current development transport's user/developer-owned API key (`KeychainStore`); no shared production key allowed |

To start clean on a machine: quit WriterFlow, delete the Application Support folder above, and remove Keychain items for WriterFlow if you want a full reset.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No floating icon | Check Accessibility is ON for `~/Applications/WriterFlow.app`; ensure the field isn’t secure; app not paused from the menu bar |
| Hotkey does nothing | Confirm **⌃⌥ Space** (Control + Option + Space); check Input Monitoring is ON |
| “Nothing to rewrite” | Type or select text first (Reply can run on empty field using conversation context) |
| Azure / stream errors in local development | Re-check `TARGET_URI` + deployment names; run `./scripts/test-azure.sh`; or use a developer-owned key in Settings |
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

[`RELEASE.md`](RELEASE.md) is the canonical runbook. The short version is:

### V1.0 — current path, no Apple membership

1. Complete every production AI, privacy, credential, version, architecture, license,
   UI, soak, and artifact gate in `RELEASE.md`.
2. Build a clean Release bundle and public DMG, then publish a SHA-256 checksum:

   ```bash
   make clean
   CONFIG=release make bundle
   make dmg
   (cd build && shasum -a 256 WriterFlow-1.0.0.dmg > WriterFlow-1.0.0.dmg.sha256)
   ```

3. Test on a clean, unmanaged Mac. The user drags WriterFlow to Applications, tries to
   open it once, then uses **System Settings → Privacy & Security → Open Anyway** and
   confirms **Open**. Never ask users to disable Gatekeeper or run `xattr`.
4. Publish the DMG, checksum, release notes, privacy disclosure, and exact macOS/CPU
   support together. Updates are manual in v1 and may require Accessibility/Input
   Monitoring approval again.

The v1 app is ad-hoc signed and unnotarized. It is publicly downloadable, but
organization-managed Macs may prohibit unidentified apps. `AppRelocator` cannot bypass the initial
Gatekeeper decision because the app cannot run before the user approves it.

### V2.0 — deferred

Apple Developer Program membership, Developer ID trust/notarization submission, ticket
stapling, Sparkle/appcast/EdDSA auto-updates, remote user or
membership databases, billing/licensing, accounts, and teams are v2-only. The existing
`make release` / `scripts/release.sh` and `WriterFlow.entitlements` are retained as v2
Developer ID scaffolding; do not use them for the v1 path.

**Diagnostics, not automated crash reporting.** Settings → Reliability → "Share
Diagnostics" writes a local text file (app/OS version, per-app AX success/fail counts,
recent crash reports macOS already collected under `~/Library/Logs/DiagnosticReports/`)
that the user explicitly saves and can choose to send — nothing is ever collected or
uploaded automatically.

**Versioning**: no `v1.0.0` tag exists yet. Cut one after the gates in `RELEASE.md`,
Phase 3/4 live verification, soak, checksum/artifact checks, and clean-Mac manual
Gatekeeper test pass. Developer ID signing and notarization are not v1 tag gates.

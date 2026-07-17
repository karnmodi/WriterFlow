# WriterFlow

Native macOS menu-bar writing assistant. While you type in any app (Gmail, WhatsApp, Slack, Notes, …), a small floating icon appears. Click it — or press **⌃⌥ Space** — to rewrite, reply, or follow a custom instruction in place. Think Whisperflow, but for typing instead of voice.

Requires **macOS 14+ on Apple Silicon (ARM64)**. Intel Macs are not supported by the v1 artifact. Not distributed via the Mac App Store (Accessibility APIs used here fail App Store review).

**v1.0.0 is published** as a public, free **bring-your-own-key** download: AI actions use the user’s Azure OpenAI endpoint and API key. It has no WriterFlow account, membership, or shared publisher key. [`RELEASE.md`](RELEASE.md) preserves the v1 production/security runbook; [`PRD-V2.md`](PRD-V2.md) defines the planned account-backed v2 release.

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

**Production status:** v1.0.0 was published on July 17, 2026 from commit `7255390`. BYO Azure is its production AI path (Setup + Settings). Passive typing does not perform network inference; opening the action menu explicitly authorizes recommendation classification.

**Architecture (source layout)**

| Folder | Role |
|---|---|
| `Sources/WriterFlow/App/` | Menu bar, onboarding (permissions + BYO Azure), settings, hotkey |
| `Sources/WriterFlow/FocusMonitor/` | AX focus + typing detection, app adapters |
| `Sources/WriterFlow/Overlay/` | Floating icon, action popover, preview card, toasts |
| `Sources/WriterFlow/Engine/` | Azure OpenAI client, prompts, replace / clipboard pipeline |
| `Sources/WriterFlow/Store/` | Local settings/data; user Keychain key + `models.json` endpoint/deployments |

Planning docs: shipped-v1 baseline in `PRD.md` / `RELEASE.md`; active-v2 requirements in [`PRD-V2.md`](PRD-V2.md), architecture in [`V2-ARCHITECTURE.md`](V2-ARCHITECTURE.md), delivery order in [`V2-ROADMAP.md`](V2-ROADMAP.md), and the next implementation checklist in [`phases/phase-5-v2-cloud-foundation.md`](phases/phase-5-v2-cloud-foundation.md). `CLAUDE.md` / `AGENTS.md` remain mirrored tool context.

---

## Local development setup

This section is for contributors. The direct Azure transport is also the published v1
BYO path; what is development-only here is the local `.env` credential bootstrap. Public
users configure their own endpoint/key in Setup or Settings, and contributor credentials
must never be copied into a release artifact.

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

The same Setup/Settings UI used by public v1 can paste and validate a user-owned key.
Contributors may use it instead of `.env`; never use either path to distribute a
maintainer/shared key.

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
| `~/Library/Application Support/WriterFlow/models.json` | User-configured Azure endpoint, deployment routing, and non-secret pricing estimates |
| `~/Library/Application Support/WriterFlow/secrets.env` | Debug/contributor builds only; release builds compile this credential fallback out |
| `~/Library/Application Support/WriterFlow/compatibility.json` | Per-app AX / context diagnostics |
| Keychain | Published v1 BYO transport's user-owned API key (or contributor-owned key in local development) via `KeychainStore`; no shared production key allowed |

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

Phase checklists live under `phases/`. V2 product requirements: `PRD-V2.md`. Changes so far: `CHANGELOG.md`.

---

## Releasing

[`RELEASE.md`](RELEASE.md) is the canonical runbook. The short version is:

### V1.0 — published baseline, no Apple membership

1. Complete every production AI, privacy, credential, version, architecture, license,
   UI, soak, and artifact gate in `RELEASE.md`.
2. Run the single-command release builder/verifier, then publish its DMG and checksum:

   ```bash
   make verify-release
   ```

3. Test on a clean, unmanaged Mac. Opening the DMG shows the branded installer window
   (WriterFlow left → Applications right). The user drags WriterFlow to Applications, tries to
   open it once, then uses **System Settings → Privacy & Security → Open Anyway** and
   confirms **Open**. Never ask users to disable Gatekeeper or run `xattr`.
4. Publish the DMG, checksum, release notes, privacy disclosure, and exact macOS/CPU
   support together. Updates are manual in v1 and may require Accessibility/Input
   Monitoring approval again.

The v1 app is ad-hoc signed and unnotarized. It is publicly downloadable, but
organization-managed Macs may prohibit unidentified apps. `AppRelocator` cannot bypass the initial
Gatekeeper decision because the app cannot run before the user approves it.

### V2.0 — planned

V2 adds real-user authentication, encrypted local storage, an authenticated WriterFlow
API with private Azure model access, PostgreSQL membership/usage state, contextual
auto-selection, multi-model routing, and Stripe-ready billing. Start with
[`phases/phase-5-v2-cloud-foundation.md`](phases/phase-5-v2-cloud-foundation.md); do not
remove the v1 options flow or enable charging before its roadmap gates pass.

**Diagnostics, not automated crash reporting.** Settings → Reliability → "Share
Diagnostics" writes a local text file (app/OS version, per-app AX success/fail counts,
recent crash reports macOS already collected under `~/Library/Logs/DiagnosticReports/`)
that the user explicitly saves and can choose to send — nothing is ever collected or
uploaded automatically.

**Versioning**: no `v1.0.0` tag exists yet. Cut one after the gates in `RELEASE.md`,
Phase 3/4 live verification, soak, checksum/artifact checks, and clean-Mac manual
Gatekeeper test pass. Developer ID signing and notarization are not v1 tag gates.

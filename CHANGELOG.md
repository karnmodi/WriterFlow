# Changelog

All notable changes to WriterFlow, grouped by development phase (see `phases/` and
`ROADMAP.md`).

## 2.0.4 — Unreleased

- **Failed generation UI:** When a rewrite fails, dismiss returns to the normal floating
  icon instead of leaving the busy/loading spinner. Soft-hide + busy icon remain only
  for recoverable in-flight or completed-unseen results.

## 2.0.3 — Unreleased

- **Preview persistence:** Esc/Close/blur soft-hides an in-flight or completed-unseen
  preview; the floating icon stays busy and restores the same streaming UI. Cancel
  stops generation; Pause still aborts as before.
- **Broader input detection:** Additive compose policies for Cursor/VS Code/chat,
  Google Docs, and Excel/Numbers without loosening global StrictFieldGate limits for
  apps that already work.
- **Terminal / Claude CLI replace:** Line-scoped Ctrl+U + paste replace for known
  terminals (no scrollback AX overwrite).

## 2.0.2 — Unreleased

- **Universal macOS release:** Release packaging now compiles native arm64 and x86_64
  slices at the macOS 14.0 deployment target, merges one universal executable, and
  ships SQLCipher's existing universal framework in a single DMG. Debug builds remain
  native-only for speed.
- **Compatibility gate:** `make compatibility-build` cross-compiles both architectures;
  release verification rejects drift between Package/Xcode/plist deployment targets,
  missing architecture slices, or bundled Mach-O code requiring newer than macOS 14.
- **Release metadata:** bumped the app to 2.0.2 (build 4) and updated public install
  copy for Apple-silicon and Intel Macs. Runtime macOS 14/15/26 hardware-matrix
  verification remains a manual Phase 8 release gate.
- **Browser sign-in:** production website token exchanges now call APIM's default
  gateway directly, avoiding Cloudflare's interactive challenge for Container Apps
  server traffic. Pairing errors retain the device code and show a support-safe API
  reference instead of the generic “Could not start a WriterFlow session” dead end.

## Unreleased — v2.0 planning

- Added the v2 product requirements, architecture, staged roadmap, and detailed Phase 5
  implementation checklist for authentication, encryption, private Azure inference,
  PostgreSQL, memberships/usage, Stripe readiness, contextual auto-selection, prompt
  enhancement, and multiple logical model routes.

## 1.0.0 — 2026-07-17

- **4.1 Clipboard fallback pipeline**: hardened the existing AX-write-fails-so-paste
  fallback with a refocus guard (aborts if the target field changed mid-request), a
  matching read-side `⌘A ⌘C` fallback for fields whose AX value can't be read
  directly, and a per-app Auto/Always/Never override.
  Deviations agreed inline in `phases/phase-4-polish-release.md`.
- **4.2 Animation & feel pass**: icon spring fade/scale-in, a spinner-morph while an
  action streams, a subtle Replace haptic, and `NSWorkspace.accessibilityDisplayShouldReduceMotion`
  respected throughout.
- **4.3 Resilience & performance**: a session-only AX kill-switch watchdog (auto-pauses
  WriterFlow for an app after 3 consecutive accessibility failures, with a Settings-tab
  note and one-click re-enable), and clearer offline/timeout error messages. Confirmed
  event-tap auto-re-enable and in-flight request cancellation were already correct from
  earlier phases.
- **4.4 Packaging hardening**: clean ARM64 Release build, hardened-runtime ad-hoc
  signing, version/architecture/signature verification, mounted-DMG secret scanning,
  bundled third-party notices, SHA-256 generation/verification, and the documented
  Gatekeeper **Open Anyway** flow. Manual updates require no Apple membership;
  Developer ID/notarization/Sparkle remain v2.
- **V1 production policy**: WriterFlow is a free BYO-key download with no WriterFlow
  account, membership, payment, remote user database, shared publisher credential, or
  custom WriterFlow API. Release builds use the user's Azure endpoint/key/deployments,
  compile out local `.env` / `secrets.env` credential paths, enforce allowlisted HTTPS
  Azure Responses endpoints, sanitize upstream errors, make one provider request per
  action, and never send field text from passive typing.

## Phase 3 — Dashboard & memory

GRDB-backed history store with retention; Dashboard shell (History tab with
search/filter/diff detail); Personalization tab (voice profile, an explicit
"Analyze My Writing Style" button — not automatic, to keep Golden Rule #2's
"only on explicit user action" intact — snippets, per-app tone/signature/instruction
rules); full Settings tab (configurable hotkey with live collision detection,
hot-reloadable per-action-class model routing, inline API key management); Usage tab
(Swift Charts, acceptance rate as the north star, editable cost pricing table). Dashboard
now opens by default on every launch; missing permissions show onboarding on top,
non-blocking. Followed by a polish pass: a shared card-based design system across all
tabs, and a real race-condition fix in Custom-instruction submission plus a
non-destructive "derivative artifact" insert mode.

## Phase 2 — Context & Reply

Per-app compatibility layer (Chrome/Electron/Safari quirks persisted to
`compatibility.json`), conversation context extraction (4k char cap, terminal-safe
current-line-only mode), Reply and Custom prompt actions, per-app tone defaults, and an
async recommendation engine that classifies the best action only after the user opens
the action menu.

## Phase 1 — Core actions

AX text read/replace (selection-preserving where possible), the action popover UI with
the global hotkey, Azure OpenAI Responses API streaming into a preview card, Copy/Retry/
undo, and the clipboard-paste fallback pipeline for apps where AX write fails.

## Phase 0 — Foundation

SPM project skeleton (no Xcode required), permissions onboarding, `AXObserver`-based
focus monitoring, the floating non-activating icon, and `SettingsStore` plumbing.

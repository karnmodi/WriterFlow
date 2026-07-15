# Changelog

All notable changes to WriterFlow, grouped by development phase (see `phases/` and
`ROADMAP.md`). No version has been tagged yet — see "Releasing" in `README.md` for
what's still gating a 1.0.0 tag.

## Unreleased — Phase 4 (polish & release), in progress

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
- **4.4 Packaging (in progress)**: `scripts/make-dmg.sh` (drag-to-Applications DMG),
  `scripts/release.sh` (Developer ID signing + notarization, needs real Apple credentials
  this dev environment doesn't have), `AppRelocator` (offers to copy itself out of a
  mounted DMG to `~/Applications` and clears the quarantine flag), and a local-only
  "Share Diagnostics" export (crash reports + compatibility counters, opt-in, never
  auto-uploaded). Sparkle 2 auto-updates deliberately **not** wired up yet — it needs a
  publicly hosted appcast + an EdDSA signing key that don't exist yet; see README.

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
async recommendation engine that classifies the best action while the user types.

## Phase 1 — Core actions

AX text read/replace (selection-preserving where possible), the action popover UI with
the global hotkey, Azure OpenAI Responses API streaming into a preview card, Copy/Retry/
undo, and the clipboard-paste fallback pipeline for apps where AX write fails.

## Phase 0 — Foundation

SPM project skeleton (no Xcode required), permissions onboarding, `AXObserver`-based
focus monitoring, the floating non-activating icon, and `SettingsStore` plumbing.

# CLAUDE.md — WriterFlow

Context file for AI-assisted development. Read this first; it tells you what the project is, where the specs live, and how to work.

## What this project is

WriterFlow is a native macOS menu bar app — an always-on, invisible writing assistant. When the user types in any app (Gmail, WhatsApp, Slack, anywhere), a small floating icon appears near the text field. Clicking it (or pressing `⌥ Space`) opens an action popover: **Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt**. It reads the field content and surrounding conversation via the macOS Accessibility API, sends it to OpenAI, streams the result into a preview card, and replaces the text in place. Think "Whisperflow, but for typing instead of voice."

## Current state

**Phase 2 complete** — app compatibility layer (`AppAdapter`, Chrome/Electron/Safari quirks, `CompatibilityMap` persisted to `compatibility.json`), conversation context extraction (`ConversationExtractor`, 4k char cap, 10s cache, terminal-safe current-line-only mode via `TerminalApps`), Reply + Custom prompt actions, per-app tone defaults, and the async Recommendation Engine (`RecommendationEngine` + `AzureOpenAIClient.classifyAction`) are all implemented and committed. Phase 1's preview card and Settings pane remain in place; the Phase 4 clipboard-fallback pipeline and field-detection hardening pulled forward during Phase 1 are unchanged.

**Phase 3 complete, including a post-stage polish pass (3.6/3.7)** — GRDB store (3.1); Dashboard shell + History tab, user-verified working (3.2); Personalization & memory — voice profile, explicit "Analyze My Writing Style" button, snippets/facts, per-app rules (3.3); full Settings tab — configurable/collision-checked hotkey recorder, icon behavior, per-action-class model deployment fields (live-apply via `models.json` hot-reload), inline API key management, clipboard-fallback toggle, launch at login, retention (3.4); Usage tab — Swift Charts for action/token volume, acceptance-rate stat as the north star, estimated cost from an editable pricing table (3.5). The standalone Phase 1.5 Settings window was retired — Dashboard is the one settings surface now. **Launch flow changed**: Dashboard opens by default on every launch/reopen regardless of permission state; missing permissions still show onboarding on top, but non-blocking (it links to the Dashboard instead of gating it).

Polish pass on top of 3.1-3.5 (commits `84189fe` phase3.6, `0169d6c` phase3.7): shared `DashboardChrome` card-based design system applied across all Dashboard tabs; Personalization layout-collapse fix (scrollable sections, memory-note detail modal); a real race condition in Custom-instruction submission fixed (`suppressBlurUntil` 300ms window guards against delayed AX blur notifications on host-app reactivation tearing down in-flight state); a non-destructive "derivative artifact" insert mode for Custom instructions (`CustomOutputParser`, `---INSERT---` marker) so things like "write a title" insert above content instead of replacing it; multi-variant preview generation (`PreviewVariants`) with arrow-key navigation in the popover; recommendation-classifier reliability fixes (raised `max_output_tokens`, longer timeout, restart throttling) so reasoning-model suggestions stop failing silently.

Stages 3.3-3.5 and the launch-flow change are still not visually verified live (no AX/Screen Recording grant in this sandbox) — pending user confirmation, but not blocking Phase 4 per the user's go-ahead.

Note: `swift test` cannot run in this sandbox — `xctest` isn't present (Command Line Tools only, no Xcode), so unit tests must be verified by the user locally or in CI. `swift build` works fine and is the correctness bar available here.

**Phase 4 code-complete** (`phases/phase-4-polish-release.md`, commits `0b4ff28`…`f1d0bdf`), everything buildable without external credentials/infrastructure done:

- **4.1 Clipboard fallback**: refocus guard before pasting, a matching `⌘A ⌘C` read-fallback for fields whose AX value can't be read directly, tri-state per-app override (`AppRule.clipboardFallback`).
- **4.2 Animation & feel**: icon spring fade/scale-in + spinner-morph while streaming (`IconState`), subtle Replace haptic, `NSWorkspace.accessibilityDisplayShouldReduceMotion` respected throughout (`animDuration` helper). Popover/preview sizing, dark/light mode, and multi-display/Spaces/fullscreen were already correct from earlier phases — audited, no changes needed.
- **4.3 Resilience**: `AXWatchdog` — session-only kill-switch, auto-pauses an app after 3 consecutive AX failures (toast + Settings-tab note + re-enable button). `ActionEngine.userFacingMessage(for:)` gives clear offline/timeout errors. Event-tap auto-re-enable and rate-limiting/cancellation were already correct — audited, no changes needed.
- **4.4 Packaging**: `scripts/make-dmg.sh` (drag-to-Applications DMG, verified locally), `AppRelocator` (self-copies out of a mounted DMG to `~/Applications`, clears quarantine), `DiagnosticsExporter` (local-only "Share Diagnostics" export, opt-in, no upload). `scripts/release.sh` + `WriterFlow.entitlements` are written and ready but **cannot run in this sandbox — no paid Apple Developer Program membership/Developer ID cert here**; the script fails fast per missing env var rather than faking success. Sparkle 2 auto-updates deliberately not started — needs a hosted appcast + EdDSA key that don't exist yet.
- **4.5 Launch checklist**: default-excluded password managers (`AppRuleStore.seedDefaultExclusionsIfNeeded`), `RemoteConfigFetcher` (opt-in, empty/disabled by default, only ever affects a fresh install's bootstrap fallback strings or unset pricing — never an existing user's configured deployments), `firstTokenMs` latency logging + a live per-app AX-success-rate table in Settings (PRD §8 metrics — instrumented, not attestable as "met" without live dogfooding), privacy copy re-reviewed and still accurate, `CHANGELOG.md` added, a v1.1 backlog seeded in `ROADMAP.md`. Deliberately did **not** tag `v1.0.0` — gated on the signing/notarization block above plus Phase 3's still-pending live-verification pass.

**Nothing further planned** — Phase 4 was the last phase in `ROADMAP.md`. What's left before an actual 1.0.0 release: (a) the user visually verifying Stages 3.3-3.5 / the Phase 3 launch-flow change and Phase 4's UI-facing work (no AX/Screen Recording grant in this sandbox), (b) an 8h memory/CPU soak test, (c) real Apple Developer ID credentials for `scripts/release.sh`, (d) a decision on where to host a Sparkle appcast before wiring up auto-updates. The v1.1 backlog in `ROADMAP.md` is explicitly out of scope until then.

### Build system deviation from original spec

The spec called for an Xcode project. This machine has only Command Line Tools installed. Build system is **Swift Package Manager** (`Package.swift`) with a bundle-wrapper script (`scripts/bundle.sh`) that produces `build/WriterFlow.app`. Info.plist lives at the repo root (SPM disallows it as a top-level resource). Everything else in the spec (AppKit + SwiftUI, `LSUIElement=YES`, folder layout, min macOS 14) is honoured. If Xcode is installed later, `Package.swift` opens in Xcode directly.

Common commands:

```
make build        # swift build
make test         # swift test
make lint         # swiftlint (brew install swiftlint first)
make bundle       # build + wrap as build/WriterFlow.app
make run          # bundle + open
```

## Source-of-truth documents

Read in this order before writing any code:

1. `PRD.md` — full product requirements: UX states, actions, context capture, dashboard, architecture diagram, privacy rules, success metrics, risks.
2. `ROADMAP.md` — phase sequencing, dependencies, definition of done, golden rules.
3. `phases/phase-N-*.md` — the phase you're implementing. Each has stages with task checklists and **Accept:** criteria. Work stage by stage; tick checkboxes (`- [ ]` → `- [x]`) as you complete tasks.

Never invent requirements — if something isn't specified in these docs, ask or propose in a comment before building.

## Tech stack (decided — do not change without discussion)

- **Language/UI:** Swift, AppKit + SwiftUI hybrid. Min target macOS 14. No Electron, no Tauri.
- **App type:** Menu bar only (`LSUIElement = YES`), no dock icon. Launch at login via `SMAppService`.
- **System integration:** Accessibility API (`AXUIElement*`), passive listen-only `CGEventTap` for typing detection, Carbon `RegisterEventHotKey` for the global hotkey.
- **Overlay:** non-activating `NSPanel` (`.nonactivatingPanel`, level `.floating`) — focus must NEVER leave the user's text field.
- **AI:** Azure OpenAI Responses API with SSE streaming. Endpoint + deployments from `.env` (dev) / hot-swappable `models.json` in Application Support. API key in Keychain (seeded from `.env`). Never hardcode model strings in logic.
- **Storage:** SQLite via GRDB (history, memory, app rules) · Keychain (API key) · UserDefaults (settings).
- **Distribution:** Developer ID + notarization + Sparkle 2. NOT Mac App Store (private AX usage would be rejected).

## Project structure (create in Phase 0, keep to it)

```
WriterFlow/
├── App/            # entry point, menu bar, onboarding, settings plumbing
├── FocusMonitor/   # AXObserver, event tap, focused-field classification
├── Overlay/        # floating icon NSPanel, action popover, preview card
├── Engine/         # OpenAI client, prompt builder, action definitions
├── Store/          # GRDB models, Keychain, settings
├── Dashboard/      # SwiftUI dashboard window (history/memory/settings/usage)
├── Adapters/       # per-app compatibility (Chrome, Electron, Safari…) — Phase 2
├── phases/         # planning docs (this repo's specs)
├── PRD.md · ROADMAP.md · CLAUDE.md
```

## Golden rules (non-negotiable)

1. **Focus:** no window we show may ever steal keyboard focus from the user's text field. Test caret-keeps-blinking after every UI change.
2. **Privacy:** text is sent to OpenAI ONLY on explicit user action. The event tap is listen-only, used solely as an "is typing" timestamp — never buffer or log key contents.
3. **Secure fields:** role `AXSecureTextField` or `IsSecureEventInputEnabled()` → WriterFlow is completely inert. No icon, no reads.
4. **Main thread:** all AX calls and network calls off-main, AX calls wrapped with a 500 ms timeout (AX can hang on busy apps).
5. **Secrets:** API key lives in Keychain only. Never in UserDefaults, logs, or source.
6. **Performance:** idle CPU < 1%, icon appears < 150 ms after first keystroke, first streamed token < 800 ms target.
7. **Graceful degradation:** AX read/write fails → clipboard fallback (Phase 4) or a clear error — never a hang or silent no-op.

## Coding conventions

- Swift Concurrency (`async/await`, actors) over GCD where possible; `@MainActor` explicitly for UI.
- One responsibility per type; components communicate via small protocols (e.g. `FocusMonitorDelegate`) so they're testable without AX.
- Prompts live in editable resource files, not inline strings.
- `os_log` with categories: `focus`, `overlay`, `engine`, `store`. No print().
- Unit tests for prompt building, diffing, store; AX behavior is verified manually per the **Accept:** criteria (list of target apps in each phase file).
- Commit per stage, message format: `phase0.3: FocusMonitor AXObserver + typing signal`.

## Known platform gotchas (learned in research — respect these)

- Chrome only exposes web content after setting `AXEnhancedUserInterface = true` on its AX app element.
- Electron apps (Slack, WhatsApp Desktop, Notion) need `AXManualAccessibility = true`.
- CGEventTaps get disabled by the OS under load — listen for `kCGEventTapDisabled(ByTimeout|ByUserInput)` and re-enable.
- AXObserver must be re-attached on every app activation (`NSWorkspace.didActivateApplicationNotification`); test rapid ⌘Tab.
- Setting full `kAXValue` destroys rich-text formatting — prefer `kAXSelectedTextRange` + `kAXSelectedText` replacement.
- OpenAI retires models quickly — model strings and pricing live in a hot-swappable config JSON.

## How to work a phase

1. Open `phases/phase-N-*.md`, read the whole file.
2. Implement stage by stage, in order. Don't start stage N+1 with stage N's Accept criteria failing.
3. Tick checkboxes in the phase file as tasks complete; note deviations inline under the task.
4. At phase end, verify the exit criteria + ROADMAP's definition of done (no regressions, CPU/memory budget).
5. Update the "Current state" section of this file to point at the next phase.

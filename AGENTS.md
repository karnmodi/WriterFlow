# AGENTS.md — WriterFlow

Context file for AI-assisted development. Read this first; it tells you what the project is, where the specs live, and how to work.

`CLAUDE.md` and `AGENTS.md` are intentional tool-specific mirrors. Update them together; their content should differ only where the filename/title itself is referenced.

## What this project is

WriterFlow is a native macOS menu bar app — an always-on, invisible writing assistant. When the user types in any app (Gmail, WhatsApp, Slack, anywhere), a small floating icon appears near the text field. Clicking it (or pressing `⌃⌥ Space`) opens an action popover: **Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt**. The app reads the field content and surrounding conversation via the macOS Accessibility API, sends it through the user’s Azure OpenAI resource (bring-your-own-key) only after explicit action, streams the result into a preview card, and replaces the text in place. Think "Whisperflow, but for typing instead of voice."

## Current state

**Phase 2 complete** — app compatibility layer (`AppAdapter`, Chrome/Electron/Safari quirks, `CompatibilityMap` persisted to `compatibility.json`), conversation context extraction (`ConversationExtractor`, 4k char cap, 10s cache, terminal-safe current-line-only mode via `TerminalApps`), Reply + Custom prompt actions, per-app tone defaults, and the async Recommendation Engine (`RecommendationEngine` + `AzureOpenAIClient.classifyAction`) are all implemented and committed. Phase 1's preview card and Settings pane remain in place; the Phase 4 clipboard-fallback pipeline and field-detection hardening pulled forward during Phase 1 are unchanged.

**Phase 3 implementation complete, including a post-stage polish pass (3.6/3.7)** — GRDB store (3.1); Dashboard shell + History tab, user-verified working (3.2); Personalization & memory — voice profile, explicit "Analyze My Writing Style" button, snippets/facts, per-app rules (3.3); full Settings tab — configurable/collision-checked hotkey recorder, icon behavior, per-action-class model deployment fields, BYO Azure endpoint + API key management, clipboard-fallback toggle, launch at login, retention (3.4); Usage tab — Swift Charts for action/token volume, acceptance-rate stat as the north star, estimated cost from an editable pricing table (3.5). The standalone Phase 1.5 Settings window was retired — Dashboard is the one settings surface now. **Launch flow changed**: Dashboard opens by default on every launch/reopen regardless of permission state; missing permissions or missing BYO Azure setup still show onboarding on top, but non-blocking (it links to the Dashboard instead of gating it).

Polish pass on top of 3.1-3.5 (commits `84189fe` phase3.6, `0169d6c` phase3.7): shared `DashboardChrome` card-based design system applied across all Dashboard tabs; Personalization layout-collapse fix (scrollable sections, memory-note detail modal); a real race condition in Custom-instruction submission fixed (`suppressBlurUntil` 300ms window guards against delayed AX blur notifications on host-app reactivation tearing down in-flight state); a non-destructive "derivative artifact" insert mode for Custom instructions (`CustomOutputParser`, `---INSERT---` marker) so things like "write a title" insert above content instead of replacing it; preview-variant infrastructure; recommendation-classifier reliability fixes. Public v1 makes one provider request per action and starts recommendation classification only after the user explicitly opens the action menu.

Stages 3.3-3.5 and the launch-flow change are still not visually verified live (no AX/Screen Recording grant in this sandbox) — pending user confirmation, but not blocking Phase 4 per the user's go-ahead.

Note: `swift test` cannot run in this sandbox — `xctest` isn't present (Command Line Tools only, no Xcode), so unit tests must be verified by the user locally or in CI. `swift build` works fine and is the correctness bar available here.

**Phase 4 feature implementation baseline complete** (`phases/phase-4-polish-release.md`, commits `0b4ff28`…`f1d0bdf`), but production readiness was reopened by the v1 release/security plan in `RELEASE.md`:

- **4.1 Clipboard fallback**: refocus guard before pasting, a matching `⌘A ⌘C` read-fallback for fields whose AX value can't be read directly, tri-state per-app override (`AppRule.clipboardFallback`).
- **4.2 Animation & feel**: icon spring fade/scale-in + spinner-morph while streaming (`IconState`), subtle Replace haptic, `NSWorkspace.accessibilityDisplayShouldReduceMotion` respected throughout (`animDuration` helper). Popover/preview sizing, dark/light mode, and multi-display/Spaces/fullscreen were already correct from earlier phases — audited, no changes needed.
- **4.3 Resilience**: `AXWatchdog` — session-only kill-switch, auto-pauses an app after 3 consecutive AX failures (toast + Settings-tab note + re-enable button). `ActionEngine.userFacingMessage(for:)` gives clear offline/timeout errors. Event-tap auto-re-enable and rate-limiting/cancellation were already correct — audited, no changes needed.
- **4.4 Packaging**: `scripts/make-dmg.sh` produces a drag-to-Applications DMG and `DiagnosticsExporter` provides a local-only, opt-in export. V1 intentionally uses an ad-hoc signature, manual Gatekeeper **Open Anyway** approval, a published checksum, and manual updates. `scripts/release.sh` + `WriterFlow.entitlements` are retained as **v2-only** Developer ID/notarization scaffolding; Apple membership is not a v1 blocker. `AppRelocator` cannot bypass initial Gatekeeper because it cannot run before the user approves the app.
- **4.5 Launch checklist**: default-excluded password managers, metrics instrumentation, and local diagnostics exist. Explicit-action-only networking is restored: passive typing never starts inference; recommendation classification begins only after the action menu is opened. Public v1 AI path is **bring-your-own-key** (user Azure endpoint + Keychain key + deployment names via Setup/Settings); publisher-shared keys remain forbidden. The `v1.0.0` tag remains gated on live UI verification, soak, artifact validation, and clean-Mac install testing — not signing/notarization.

**Production readiness** — before an actual 1.0.0 release: (a) BYO Azure path is the approved public transport (done in product policy; keep artifact free of `.env`/shared keys), (b) restore explicit-action-only network behavior, (c) harden HTTPS destination/error handling and secret-scan the DMG, (d) complete the pending Phase 3/4 live verification and eight-hour soak, and (e) produce a versioned, checksum-published artifact for every advertised CPU architecture and test Apple's manual Gatekeeper flow on a clean Mac. Remote user/membership databases, Apple Developer membership, Developer ID/notarization, Sparkle, billing/licensing, and teams are v2-only.

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
3. `RELEASE.md` — canonical v1 production/security gates, packaging runbook, and v1/v2 infrastructure split.
4. `phases/phase-N-*.md` — the phase you're implementing. Each has stages with task checklists and **Accept:** criteria. Work stage by stage; tick checkboxes (`- [ ]` → `- [x]`) as you complete tasks.

Never invent requirements — if something isn't specified in these docs, ask or propose in a comment before building.

## Tech stack (decided — do not change without discussion)

- **Language/UI:** Swift, AppKit + SwiftUI hybrid. Min target macOS 14. No Electron, no Tauri.
- **App type:** Menu bar only (`LSUIElement = YES`), no dock icon. Launch at login via `SMAppService`.
- **System integration:** Accessibility API (`AXUIElement*`), passive listen-only `CGEventTap` for typing detection, Carbon `RegisterEventHotKey` for the global hotkey.
- **Overlay:** non-activating `NSPanel` (`.nonactivatingPanel`, level `.floating`) — focus must NEVER leave the user's text field.
- **AI:** Production v1 is **bring-your-own-key**: the user configures their Azure OpenAI Responses endpoint, API key (Keychain only), and deployment names in Setup / Settings. No publisher-owned/shared reusable service credential may ship in the app. Local `.env` / `secrets.env` bootstrap is contributor-only. No bespoke WriterFlow API. A future provider-managed no-key transport is v2-optional.
- **Storage:** local SQLite via GRDB (history, memory, app rules) · UserDefaults (settings). No remote user/account/membership/billing/sync database in v1. Public v1 stores no AI provider credential in Keychain; a future provider-issued device token is allowed only after the lifecycle/security review in `RELEASE.md`.
- **Distribution:** V1 = public DMG containing an ad-hoc-signed app + SHA-256 + manual Gatekeeper approval/manual updates, with no Apple membership. V2 = Developer ID + notarization + Sparkle 2. NOT Mac App Store (private AX usage would be rejected).

## Project structure (create in Phase 0, keep to it)

```
WriterFlow/
├── App/            # entry point, menu bar, onboarding, settings plumbing
├── FocusMonitor/   # AXObserver, event tap, focused-field classification
├── Overlay/        # floating icon NSPanel, action popover, preview card
├── Engine/         # AI transport, prompt builder, action definitions
├── Store/          # GRDB models, Keychain, settings
├── Dashboard/      # SwiftUI dashboard window (history/memory/settings/usage)
├── Adapters/       # per-app compatibility (Chrome, Electron, Safari…) — Phase 2
├── phases/         # planning docs (this repo's specs)
├── PRD.md · ROADMAP.md · RELEASE.md · AGENTS.md
```

## Golden rules (non-negotiable)

1. **Focus:** no window we show may ever steal keyboard focus from the user's text field. Test caret-keeps-blinking after every UI change.
2. **Privacy:** in production, text is sent to the selected AI processing service ONLY on explicit user action. The event tap is listen-only, used solely as an "is typing" timestamp — never buffer or log key contents. Recommendation classification starts only after the user explicitly opens the action menu.
3. **Secure fields:** role `AXSecureTextField` or `IsSecureEventInputEnabled()` → WriterFlow is completely inert. No icon, no reads.
4. **Main thread:** all AX calls and network calls off-main, AX calls wrapped with a 500 ms timeout (AX can hang on busy apps).
5. **Secrets:** no publisher-owned/shared reusable service credential may be embedded, bundled, downloaded, copied to Application Support, persisted in Keychain/UserDefaults, or logged by a production client. Development credentials stay local and never enter a public artifact. Any provider-issued device token needs an explicitly supported public-client lifecycle and security review.
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
- AI providers retire models quickly — production routing belongs on the provider platform once selected. A client may consume only a validated static, non-secret fallback config; never credentials or an arbitrary service contract.

## How to work a phase

1. Open `phases/phase-N-*.md`, read the whole file.
2. Implement stage by stage, in order. Don't start stage N+1 with stage N's Accept criteria failing.
3. Tick checkboxes in the phase file as tasks complete; note deviations inline under the task.
4. At phase end, verify the exit criteria + ROADMAP's definition of done (no regressions, CPU/memory budget).
5. Update the "Current state" section of this file to point at the next phase.

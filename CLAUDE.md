# CLAUDE.md — WriterFlow

Context file for AI-assisted development. Read this first; it tells you what the project is, where the specs live, and how to work.

## What this project is

WriterFlow is a native macOS menu bar app — an always-on, invisible writing assistant. When the user types in any app (Gmail, WhatsApp, Slack, anywhere), a small floating icon appears near the text field. Clicking it (or pressing `⌥ Space`) opens an action popover: **Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt**. It reads the field content and surrounding conversation via the macOS Accessibility API, sends it to OpenAI, streams the result into a preview card, and replaces the text in place. Think "Whisperflow, but for typing instead of voice."

## Current state

**Phase 1 complete** — preview card (streaming, Replace/Copy/Retry/Discard, Fix Grammar diff hint, restore-original undo chip, `ConversionEvent.accepted` tracking) and the Settings pane (paste + validate + Keychain-store an Azure API key) are both done. The Phase 4 clipboard-fallback pipeline (`TextInserter`/`ClipboardWriter`) and field-detection hardening (`StrictFieldGate`/`CaretEstimator`/`FocusedElementResolver`) were pulled forward during Phase 1 as part of making text replacement reliable. Next: Phase 2 (context awareness, reply, custom prompt).

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

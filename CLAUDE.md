# CLAUDE.md — WriterFlow

Context file for AI-assisted development. Read this first; it tells you what the project is, where the specs live, and how to work.

`CLAUDE.md` and `AGENTS.md` are intentional tool-specific mirrors. Update them together; their content should differ only where the filename/title itself is referenced.

## What this project is

WriterFlow is a native macOS menu bar app — an always-on, invisible writing assistant. When the user types in any app (Gmail, WhatsApp, Slack, anywhere), a small floating icon appears near the text field. Clicking it (or pressing `⌃⌥ Space`) opens an action popover: **Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt**. The app reads the field content and surrounding conversation via the macOS Accessibility API, sends it through the user’s Azure OpenAI resource (bring-your-own-key) only after explicit action, streams the result into a preview card, and replaces the text in place. Think "Whisperflow, but for typing instead of voice."

## Current state

**V1.0.0 is published** from tag `v1.0.0` at commit `7255390` (July 17,
2026). The shipped product is the completed Phase 0–4 native macOS app: AX focus/context
capture, non-activating overlay, action popover and prompt builder, streamed preview,
in-place/clipboard replacement, local GRDB history/memory/rules, Dashboard, resilience,
and the ARM64 ad-hoc-signed DMG. Its production AI transport is bring-your-own Azure
OpenAI endpoint/key/deployment configuration; the user's key is stored in that user's
Keychain and no publisher-owned/shared credential ships in the app.

**V2.0 is planned; implementation has not started.** The active v2 sources of truth are
`PRD-V2.md`, `V2-ARCHITECTURE.md`, `V2-ROADMAP.md`, and
`phases/phase-5-v2-cloud-foundation.md`. The explicit product-policy change for v2 is a
WriterFlow-operated authenticated backend: Entra External ID, encrypted local data,
PostgreSQL, a public authenticated edge with private Azure origin/model access,
server-authoritative usage/entitlements, Stripe-ready billing, contextual auto selection,
prompt enhancement, and server-side multi-model routing. Phase 5 changes transport and
identity first while preserving the v1 action UI; Phase 6 removes the normal options
flow only after classifier evaluation passes.

Note: this machine has only Command Line Tools. `swift build` works; `swift test` may
remain unavailable when `xctest` is absent, so tests must run in Xcode/CI where required.

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

1. `PRD.md` — shipped v1 product requirements and historical baseline.
2. `PRD-V2.md` — active v2 product requirements and release criteria.
3. `ROADMAP.md` — master phase index and golden rules.
4. `V2-ARCHITECTURE.md` — v2 auth, API, encryption, database, Azure, Stripe, classifier, and prompt decisions.
5. `V2-ROADMAP.md` — v2 phase order, dependencies, and staged delivery path.
6. `RELEASE.md` — historical/canonical v1 packaging and security runbook.
7. `phases/phase-N-*.md` — the phase being implemented, with ordered task checklists and **Accept:** criteria. Phase 5 is next.

Never invent requirements — if something isn't specified in these docs, ask or propose in a comment before building.

## Tech stack (decided — do not change without discussion)

- **Language/UI:** Swift, AppKit + SwiftUI hybrid. Min target macOS 14. No Electron, no Tauri.
- **App type:** Menu bar only (`LSUIElement = YES`), no dock icon. Launch at login via `SMAppService`.
- **System integration:** Accessibility API (`AXUIElement*`), passive listen-only `CGEventTap` for typing detection, Carbon `RegisterEventHotKey` for the global hotkey.
- **Overlay:** non-activating `NSPanel` (`.nonactivatingPanel`, level `.floating`) — focus must NEVER leave the user's text field.
- **AI:** Production v1 is **bring-your-own-key**: the user configures their Azure OpenAI Responses endpoint, their API key (Keychain only), and deployment names. V2 deliberately replaces this with a WriterFlow authenticated SSE API; Azure credentials/deployments and prompt/model routing are server-side, with managed identity and private endpoints. No publisher-owned/shared reusable service credential may ship in any client.
- **Storage:** V1 uses local SQLite via GRDB plus UserDefaults. V2 keeps GRDB but encrypts it with SQLCipher, moves user content out of UserDefaults, and adds private managed PostgreSQL for identity/membership/entitlement/usage state. Raw cloud inference content is ephemeral by default.
- **Backend (v2):** Microsoft Entra External ID · Azure API Management · TypeScript/Fastify on Azure Container Apps · Azure Database for PostgreSQL Flexible Server · Key Vault/App Configuration · Stripe. Do not substitute a different stack without updating the v2 ADR/specs.
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
├── services/       # v2 API, worker, shared schemas
├── infra/          # v2 Bicep and API Management policy
├── prompts/        # v2 versioned server prompt resources and evals
├── phases/         # planning docs (this repo's specs)
├── PRD.md · PRD-V2.md · ROADMAP.md · V2-*.md · RELEASE.md · CLAUDE.md
```

## Golden rules (non-negotiable)

1. **Focus:** no window we show may ever steal keyboard focus from the user's text field. Test caret-keeps-blinking after every UI change.
2. **Privacy:** in production, text is sent to the selected AI processing service ONLY on explicit user action. The event tap is listen-only, used solely as an "is typing" timestamp — never buffer or log key contents. V1 classification begins after the action menu opens; v2 auto selection/classification may begin only after the user clicks the icon or presses the explicit hotkey.
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

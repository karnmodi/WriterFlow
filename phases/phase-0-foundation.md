# Phase 0 — Foundation & Skeleton

**Goal:** An invisible menu bar app that detects typing anywhere and shows/hides a floating icon near the focused field. No AI yet.

## Stage 0.1 — Project setup

- [x] ~~Xcode project~~ SPM project (Xcode not installed on this machine — only CLT): Swift, AppKit + SwiftUI, min target macOS 14. `Package.swift` produces an executable; `scripts/bundle.sh` wraps it as `WriterFlow.app` with `Info.plist`.
- [x] `LSUIElement = YES` in Info.plist (no dock icon).
- [x] Menu bar item (`NSStatusItem`) with menu: Pause, Open Dashboard (stub), Settings (stub), Quit.
- [x] SwiftLint + a `Makefile` for build-run-test (`make build|test|lint|bundle|run|clean`). SwiftLint requires `brew install swiftlint`.
- [x] Git repo with `.gitignore`; folders: `App/`, `FocusMonitor/`, `Overlay/`, `Engine/`, `Store/`, `Dashboard/`, `Adapters/`.

**Accept:** `make run` produces `build/WriterFlow.app` (ad-hoc signed, bundle id `com.karan.writerflow`, `LSUIElement=true`, min system 14.0), launches into the menu bar, no dock icon, Quit menu item terminates cleanly.

## Stage 0.2 — Permissions onboarding

- [ ] Detect Accessibility permission: `AXIsProcessTrustedWithOptions`.
- [ ] Detect Input Monitoring: `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`.
- [ ] First-launch onboarding window (SwiftUI): 2 steps, one per permission, with a "Open System Settings" deep link (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) and a live green check when granted (poll every 1 s).
- [ ] App functions in "degraded" mode without permissions (menu bar only + persistent hint).

**Accept:** Fresh install → both permissions granted through the flow without touching System Settings manually beyond the deep link.

## Stage 0.3 — FocusMonitor

- [ ] `AXObserver` on the frontmost app for `kAXFocusedUIElementChangedNotification`; re-attach on app switch (`NSWorkspace.didActivateApplicationNotification`).
- [ ] Passive CGEventTap (`.listenOnly`, `keyDown`) as the "user is typing" signal. **Do not store key contents** — only bump a timestamp.
- [ ] Classify focused element: is it text-editable? (`kAXRoleAttribute` in {`AXTextField`, `AXTextArea`, `AXComboBox`} or `kAXValueAttribute` settable; web content: role `AXTextField`/`contenteditable` heuristics).
- [ ] Secure-field guard: role `AXSecureTextField` OR `IsSecureEventInputEnabled()` → treat as non-editable.
- [ ] Emit events: `fieldFocused(frame:appBundleID:)`, `typingStarted`, `typingStopped(after: 4s debounce)`, `fieldBlurred`.
- [ ] Get field screen frame via `kAXPositionAttribute` + `kAXSizeAttribute` for icon placement.

**Accept:** Console-log events fire correctly in: TextEdit, Notes, Safari (Gmail), Chrome (Gmail), Slack. Password fields never fire.

## Stage 0.4 — Floating icon (OverlayController)

- [ ] `NSPanel` subclass: `.nonactivatingPanel`, level `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, transparent background, ignores mouse events except on the icon itself.
- [ ] 28 px pill icon (SF Symbol or asset), positioned at bottom-right of the focused field's frame, clamped to screen bounds.
- [ ] Fade in ≤150 ms on `typingStarted`; fade out on `typingStopped`/`fieldBlurred`.
- [ ] Follows field when window moves/scrolls (poll frame at 10 Hz only while visible).
- [ ] Click → placeholder popover ("Actions coming in Phase 1").
- [ ] Clicking icon never steals focus from the text field (verify caret keeps blinking).

**Accept:** Type in Gmail (Chrome), WhatsApp Desktop, Notes → icon appears near field within 150 ms, disappears 4 s after stopping, never steals focus, never appears on password fields.

## Stage 0.5 — Plumbing

- [ ] `UserDefaults`-backed settings store (icon mode: on-typing / hotkey-only / always-on-focus).
- [ ] Launch-at-login via `SMAppService.mainApp`.
- [ ] Pause toggle in menu bar (suspends event tap + observers).
- [ ] Basic os_log categories: focus, overlay, engine.

**Accept:** Survives reboot with launch-at-login; Pause fully stops icon behavior; idle CPU < 1%.

## Risks in this phase

- AXObserver detaching on app switch — re-attach logic must be bulletproof (test rapid ⌘Tab).
- Chrome exposes web fields only after `AXEnhancedUserInterface = true` is set on its AX app element — set it on first focus of a Chrome window (full handling in Phase 2, basic flag-set here).

# Phase 4 — Polish, Fallbacks & Release

**Goal:** Make it feel like a real product — smooth, resilient, installable, auto-updating.

## Stage 4.1 — Clipboard fallback pipeline ✅

For apps where AX write fails (tracked in the compatibility map):

- [x] Save current clipboard (all types, incl. images) → set rewritten text → simulate `⌘A` (if replacing all) or rely on existing selection → `⌘V` via CGEvent → restore clipboard after 300 ms. *(Already built in Phase 1 — `ClipboardWriter.executePaste` + `TextInserter.replace`'s tier-3 fallback, generic `NSPasteboardItem` save/restore covers all pasteboard types.)*
- [x] Guard: only when the original field is still focused (re-check AX focus before injecting). *(New: `ClipboardWriter.executePaste` now takes `preText`/`isWeb` and aborts the paste — returning the existing "text is on your clipboard" error path — if the freshly-read field value no longer overlaps what it held when the action started, e.g. the user tabbed to a different field in the same app during the streaming round-trip.)*
- [x] Settings toggle (default on) + per-app override. *(Deviation, noted here per CLAUDE.md: the existing global `SettingsStore.forceClipboardFallback` toggle — shipped in Stage 3.4 — forces skipping the AX tiers entirely, defaulted **off**; the automatic tier-3 fallback-when-AX-fails is unconditional/always-on regardless of that toggle, which already satisfies "default on" for the fallback mechanism itself. Defaulting the *force* toggle to on would make every app skip AX writes, needlessly destroying rich-text formatting Golden Rule #... prefers `kAXSelectedTextRange` for — so its default was left as-is. Added the missing piece: a tri-state per-app override, `AppRule.clipboardFallback: Bool?` — `nil` inherits the global default, `true` forces clipboard for that app, `false` disables clipboard paste entirely for that app (fails loudly instead). Editable via a segmented Auto/Always/Never picker in the Personalization tab's per-app rule row.)*
- [x] Same for **read** fallback: `⌘A ⌘C`, read clipboard, restore selection where possible. *(New: `ClipboardWriter.executeCopyAll` + `ContextExtractor` now distinguishes "kAXValue unreadable" (nil) from "legitimately empty" (`""`) and only falls back to `⌘A ⌘C` in the unreadable case, restoring the prior `AXSelectedTextRange` and the user's clipboard afterward. Deliberately excluded for terminal apps — a scrollback-wide `⌘A ⌘C` would leak the whole history, defeating `TerminalApps.currentLine`'s deliberate line-scoping privacy safeguard. Also wired up `CompatibilityMap.recordRead`, which existed since Phase 1 but was never actually called anywhere until now.)*

**Accept:** An app with broken AX write (test with one from the compatibility map) still gets in-place replacement; user clipboard contents restored intact. *(Code-complete + `swift build` clean; not yet exercised live against a real broken-AX app in this sandbox — no AX grant. Verify manually per CLAUDE.md when convenient.)*

## Stage 4.2 — Animation & feel pass ✅

- [x] Icon: spring fade/scale in (150 ms), gentle idle, spinner morph while streaming. *(`showIcon()` now starts the panel frame ~12% inset and animates it up to full size alongside the fade, 150ms ease-out. The wave-line idle animation already existed (Phase 1). Added `IconState` (`ObservableObject`) so the already-mounted `FloatingIconView` can cross-fade the wave icon into a small `ProgressView` while `previewStreaming` is true — wired via a `didSet` on `previewStreaming` rather than touching each of its 6 assignment sites individually.)*
- [x] Popover/preview: 120 ms ease, no layout jumps while streaming (reserve height). *(Already correct since Phase 1/2 — `popoverSize`/`previewSize`/`promptBuilderPreviewSize` are fixed-size panel frames set once at open time, not resized as streamed content grows, so there's no layout jump to fix. Left as-is.)*
- [x] Sound-free by default; optional subtle haptic on Replace (Force Touch trackpads). *(Added `NSHapticFeedbackManager.defaultPerformer.perform(.generic, ...)` in `applyPreview`'s success path — silently a no-op on Macs/trackpads without the Taptic Engine, no sound anywhere.)*
- [x] Dark/light mode audit; reduced-motion respect (`NSWorkspace.accessibilityDisplayShouldReduceMotion`). *(Audit: `ActionPopoverView`/`PreviewCardView` already use `.thinMaterial`/semantic colors throughout, so they already adapt — no changes needed there. The floating wave icon's fixed light-gray/black styling is deliberate (Phase 1 design: a stable marker that reads the same over arbitrary host-app content, not a themed chrome element) — left as-is. Reduced motion: added a shared `animDuration(_:)` helper so every `NSAnimationContext` fade in `OverlayController` collapses to instant when the flag is set, and the icon's scale-in and the continuous wave animation (`WaveLinesIconView`) both skip their motion entirely (fade-only / static) under reduced motion.)*
- [x] Multi-display + Spaces + fullscreen apps: icon positions correctly everywhere. *(Already correct since Phase 1 — `screenForField` picks the `NSScreen` that intersects the focused field's frame for every reposition, and `FloatingPanel.collectionBehavior` already includes `.canJoinAllSpaces, .fullScreenAuxiliary, .transient`. No code change needed; still only manually verifiable live, no AX grant in this sandbox.)*

**Accept:** 10-person "does this feel native?" gut-check — no jank reports; fullscreen Chrome + external monitor both correct. *(Code-complete + `swift build` clean; the actual gut-check needs a live multi-person pass the user will need to run outside this sandbox.)*

## Stage 4.3 — Resilience & performance

- [ ] Kill-switch watchdog: if AX calls hang 3× in an app, auto-disable WriterFlow for that app for the session (toast + dashboard note).
- [ ] Event tap auto-re-enable (taps get disabled by the OS under load — listen for `kCGEventTapDisabled*`).
- [ ] Memory/CPU soak test: 8 h run, < 80 MB RSS, < 1% idle CPU.
- [ ] Offline mode: clear error, actions queue is NOT kept (no surprise sends later).
- [ ] Rate limiting: max 1 in-flight request; rapid re-invokes cancel the previous.

## Stage 4.4 — Packaging & distribution

- [ ] Developer ID signing + hardened runtime + notarization (`notarytool`).
- [ ] DMG with drag-to-Applications; app moves itself out of quarantine gracefully.
- [ ] Sparkle 2 auto-updates (appcast on GitHub Pages/S3).
- [ ] Crash reporting: local crash log collection + "share diagnostics" button (opt-in, no auto-upload).
- [ ] `README.md` for the repo: build instructions, architecture map, permissions explainer.
- [ ] Version 1.0.0 tag; changelog.

**Accept:** Clean Mac (no dev tools): download DMG → install → onboard → first rewrite in < 3 minutes.

## Stage 4.5 — Launch checklist

- [ ] All PRD §8 success metrics measured and met.
- [ ] Privacy copy reviewed: onboarding + README state exactly what is read, when, and where it goes.
- [ ] Excluded-by-default list shipped: password managers, banking apps.
- [ ] Model config remotely updatable (fetch on launch, cached) so OpenAI model retirements don't brick the app.
- [ ] Backlog seeded for v1.1: multi-language reply polish, offline grammar via Apple Foundation Models, Windows feasibility spike, licensing/team model.

## Exit criteria

You use it every day without thinking about it. That's the bar.

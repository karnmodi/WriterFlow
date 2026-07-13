# Phase 4 — Polish, Fallbacks & Release

**Goal:** Make it feel like a real product — smooth, resilient, installable, auto-updating.

## Stage 4.1 — Clipboard fallback pipeline

For apps where AX write fails (tracked in the compatibility map):

- [ ] Save current clipboard (all types, incl. images) → set rewritten text → simulate `⌘A` (if replacing all) or rely on existing selection → `⌘V` via CGEvent → restore clipboard after 300 ms.
- [ ] Guard: only when the original field is still focused (re-check AX focus before injecting).
- [ ] Settings toggle (default on) + per-app override.
- [ ] Same for **read** fallback: `⌘A ⌘C`, read clipboard, restore selection where possible.

**Accept:** An app with broken AX write (test with one from the compatibility map) still gets in-place replacement; user clipboard contents restored intact.

## Stage 4.2 — Animation & feel pass

- [ ] Icon: spring fade/scale in (150 ms), gentle idle, spinner morph while streaming.
- [ ] Popover/preview: 120 ms ease, no layout jumps while streaming (reserve height).
- [ ] Sound-free by default; optional subtle haptic on Replace (Force Touch trackpads).
- [ ] Dark/light mode audit; reduced-motion respect (`NSWorkspace.accessibilityDisplayShouldReduceMotion`).
- [ ] Multi-display + Spaces + fullscreen apps: icon positions correctly everywhere.

**Accept:** 10-person "does this feel native?" gut-check — no jank reports; fullscreen Chrome + external monitor both correct.

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

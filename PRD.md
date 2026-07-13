# WriterFlow — Product Requirements Document

**Version:** 1.0 · **Date:** July 13, 2026 · **Owner:** Karan
**One-liner:** A Whisperflow-style, always-on macOS writing assistant. Invisible until you type — then a small floating icon appears near your cursor with one-tap AI actions (Elaborate, Formal, Casual, Fix Grammar, Reply, Custom) powered by OpenAI. Works in any app: Gmail, WhatsApp, Slack, Notion, anywhere text is typed.

---

## 1. Problem & Goal

Rewriting text with AI today means copy → open ChatGPT → paste → prompt → copy → paste back. That breaks flow. WriterFlow removes all of that: the assistant lives where you type, understands the surrounding context (email thread, chat history), and rewrites in-place in under 2 seconds.

**Goals**
- Zero-friction: never leave the current app; no copy-paste round trips.
- Context-aware: reads the input field content and visible conversation context via macOS Accessibility API.
- Invisible-first: no windows, no dock icon. Only a tiny floating icon while typing, plus a menu bar glyph.
- Smooth: <150 ms icon appearance, streamed AI output, native-feel animations.

**Non-goals (v1)**
- Voice dictation (that's Whisperflow's job — we're the typing counterpart).
- Windows/Linux support.
- Mac App Store distribution (Accessibility APIs used here fail App Store review — distribute as notarized direct download).

---

## 2. Target User

Primary: Karan (and later, professionals writing emails/messages all day who want confidence in their English phrasing and speed). Persona traits: technically capable, writes across Gmail, WhatsApp Web/Desktop, Slack, LinkedIn; wants natural, native-sounding output; values speed over configurability.

---

## 3. Core User Experience

### 3.1 States

| State | What the user sees |
|---|---|
| Idle | Nothing except a small menu bar icon. App runs in background, launches at login. |
| Typing detected | A ~28 px floating pill icon fades in near the caret / focused field (bottom-right corner of the field). Disappears 4 s after typing stops or on field blur. |
| Icon clicked OR hotkey (default `⌥ Space`) | Action popover opens: Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt box. Rendered as a compact non-activating panel so focus never leaves the text field. |
| Action running | Icon shows a subtle spinner; result streams into a preview card. |
| Preview | Shows rewritten text with **Replace** (Enter), **Copy**, **Retry**, **Discard** (Esc). One keypress to accept. |

### 3.2 Actions (MVP)

1. **Elaborate** — expand brief/rough text into fuller, clearer writing. Keeps intent and tone.
2. **Formal** — professional register (emails, LinkedIn).
3. **Casual** — friendly, natural register (WhatsApp, Slack).
4. **Fix Grammar** — corrections only; minimal rewording; preserves voice.
5. **Reply** — reads visible conversation context (email thread above the draft, chat history) and drafts a contextual reply. If the user has typed a rough draft, it's treated as the reply's intent.
6. **Custom** — free-text instruction box ("make it 2 lines", "add a deadline ask"), applied to the current text + context.

Each action applies to: selected text if any, else the full content of the focused field.

### 3.3 Context capture

- **Field content + selection:** via Accessibility API (`AXUIElementCreateSystemWide` → `kAXFocusedUIElementAttribute` → `kAXValue`, `kAXSelectedText`, `kAXSelectedTextRange`).
- **Surrounding context (for Reply):** walk the AX tree of the focused window to extract visible static text (email thread, chat bubbles), capped at ~4,000 chars, most-recent-first.
- **App identity:** bundle ID of frontmost app (e.g., `com.google.Chrome` + page title) → used to auto-pick tone defaults (Gmail → formal bias, WhatsApp → casual bias).
- **Fallbacks:**
  - Chrome: set `AXEnhancedUserInterface = true` on the app element to expose web content.
  - Electron apps (Slack, WhatsApp Desktop, Notion): set `AXManualAccessibility = true`.
  - If AX read fails entirely: fall back to simulated `⌘A ⌘C` clipboard capture (restore clipboard afterwards), with a settings toggle.
- **Hard exclusions:** never read secure/password fields (`kAXSecureTextField` role, or when `IsSecureEventInputEnabled()` is true) — the icon simply doesn't appear.

### 3.4 Text replacement

Primary: write back via `kAXValue`/`kAXSelectedText` (instant, no clipboard). Fallback: clipboard-paste injection (`⌘V` via CGEvent) with clipboard restore. Always undoable with the app's native `⌘Z` where possible; otherwise WriterFlow keeps a 1-step restore in the preview card.

---

## 4. Dashboard

A regular window opened from the menu bar icon (`Open Dashboard`). Tabs:

1. **History** — every conversion: timestamp, source app, action used, before → after diff view, copy buttons. Searchable. Local-only.
2. **Personalization / Memory**
   - **Voice profile:** learned from accepted rewrites (preferred greetings, sign-offs, sentence length, formality bias). Editable as plain-text "About my writing style" notes that get injected into prompts.
   - **Per-app rules:** e.g., "Gmail → always formal, sign as Karan", "WhatsApp → casual, no sign-off".
   - **Snippets/facts:** name, role, company, common phrases the model may use.
3. **Settings** — hotkey, icon behavior (always/on-typing/hotkey-only), model selection, OpenAI API key (stored in macOS Keychain), excluded apps list, clipboard-fallback toggle, launch at login.
4. **Usage** — tokens/cost estimate per day, action counts.

---

## 5. Architecture

**Stack: native Swift (AppKit + SwiftUI).** Chosen over Electron/Tauri because the whole product is deep macOS integration (AX API, non-activating panels, event taps, Keychain); native gives the smoothness requirement for free and idles at ~40 MB RAM.

```
┌────────────────────────── WriterFlow.app (menu bar, LSUIElement) ─────────────────────────┐
│                                                                                           │
│  FocusMonitor          OverlayController          ActionEngine            Dashboard        │
│  (AXObserver on        (NSPanel, non-activating,  (prompt builder +       (SwiftUI window) │
│  focus/typing events)   .floating level, fades     OpenAI client,                          │
│         │               near caret)                streaming)                  │           │
│         ▼                    │                         │                       │           │
│  ContextExtractor ───────────┴────► PreviewCard ◄──────┘                       │           │
│  (AX tree walk, app rules)          (replace/copy/retry)                       │           │
│                                                                                │           │
│  Store: SQLite (history, memory) · Keychain (API key) · UserDefaults (settings)┘           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

**Key components**

- **FocusMonitor:** `AXObserver` for `kAXFocusedUIElementChangedNotification` + a passive CGEventTap (listen-only) to detect keystrokes → drives icon show/hide. Debounced; <1% CPU idle.
- **OverlayController:** non-activating `NSPanel` (`.nonactivatingPanel`, window level `.floating`, ignores mouse until hover) positioned from the focused element's AX frame. This is what makes it "smooth" — focus never leaves the user's field.
- **ActionEngine:** builds prompt = system prompt (voice profile + per-app rule) + context block + user text + action instruction. Calls OpenAI Responses API with streaming; first token target <800 ms.
- **Model:** `gpt-5.4-mini` default (fast/cheap production default, ~2x faster and ~70% cheaper than the flagship), `gpt-5.4-nano` for Fix Grammar, flagship optional in settings for Custom/Reply. Model names configurable — pin exact strings in a config so retirements don't break the app.
- **Global hotkey:** `⌥ Space` via Carbon `RegisterEventHotKey` (configurable).

**Permissions required:** Accessibility (System Settings → Privacy & Security → Accessibility) and Input Monitoring. Onboarding flow walks through granting both, with live status checks.

---

## 6. Privacy & Security

- API key in Keychain; never logged.
- All history/memory stored locally (SQLite in `~/Library/Application Support/WriterFlow`). No WriterFlow server; the only network call is to OpenAI.
- Per-app exclusion list (e.g., 1Password, banking apps) — AX reads never occur there.
- Secure input fields always ignored.
- One-click "pause WriterFlow" from the menu bar.
- Data sent to OpenAI: only on explicit user action (never passive keystroke streaming). Keystroke monitoring is used solely as a local "is typing" signal — key contents are not buffered or stored.

---

## 7. Milestones

Development is AI-assisted (Claude Code / Cursor) — phases are ordered by dependency, not calendar time. Detailed breakdowns live in `phases/`. See `ROADMAP.md` for sequencing and `CLAUDE.md` for AI-development context.

| Phase | Scope | Detail file |
|---|---|---|
| **P0 — Skeleton** | Menu bar app, permissions onboarding, FocusMonitor, floating icon shows/hides on typing | `phases/phase-0-foundation.md` |
| **P1 — Core actions** | AX read/replace, popover with Core 4 actions, OpenAI streaming, preview card, hotkey | `phases/phase-1-core-actions.md` |
| **P2 — Context & Reply** | AX tree context extraction, per-app tone defaults, Reply + Custom actions, Chrome/Electron fallbacks | `phases/phase-2-context-reply.md` |
| **P3 — Dashboard & memory** | History, voice profile, per-app rules, usage stats, settings | `phases/phase-3-dashboard-memory.md` |
| **P4 — Polish** | Animations, clipboard fallback, excluded apps, notarized DMG, login item | `phases/phase-4-polish-release.md` |

---

## 8. Success Metrics

- Icon appears within 150 ms of first keystroke in a field.
- First streamed token < 800 ms; full rewrite of a 100-word email < 2.5 s.
- Replace-in-place works in: Gmail (Chrome + Safari), WhatsApp Desktop, Slack, Apple Mail, Notes, Notion, LinkedIn (Chrome). ≥ 90% AX success rate across these; clipboard fallback covers the rest.
- Daily usage: ≥ 10 actions/day by week 2 of dogfooding; ≥ 60% of previews accepted (Replace).

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| AX API blocked/flaky in some apps (esp. web views) | Chrome/Electron AX flags + clipboard fallback; per-app compatibility table maintained in-app |
| Mac App Store rejection (private AX usage) | Direct distribution, notarized; Sparkle for auto-updates |
| OpenAI model retirements (e.g., GPT-4.1 retired Apr 2026) | Model strings in remote-updatable config; settings override |
| Latency spikes ruin "smooth" feel | Streaming UI, optimistic spinner, nano model for grammar, request timeout + retry |
| Privacy concerns from keystroke monitoring | Listen-only local signal, clear onboarding copy, open pause control |

---

## 10. Open Questions

1. Should Reply mode support multi-language (detect Hindi/Hinglish input, reply in same language)? — likely yes, cheap to add via prompt.
2. Local model fallback (Apple Foundation Models) for offline grammar fixes? — post-v1.
3. Team/licensing model if this becomes a side-venture product? — out of scope for v1.

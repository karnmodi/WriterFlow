# WriterFlow — Product Requirements Document

**Version:** 1.0 · **Date:** July 16, 2026 · **Owner:** Karan

> **Shipped-v1 baseline:** v1.0.0 was published July 17, 2026. This document is retained
> as the v1 product specification; [`PRD-V2.md`](PRD-V2.md) supersedes it for v2 work.
> Where older v1 wording conflicts, the shipped code and [`RELEASE.md`](RELEASE.md)
> define the v1 security/transport behavior.

**One-liner:** A Whisperflow-style, always-on macOS writing assistant. Invisible until you type — then a small floating icon appears near your cursor with one-tap AI actions (Elaborate, Formal, Casual, Fix Grammar, Reply, Custom) powered by the user's Azure OpenAI resource in v1. Works in any app: Gmail, WhatsApp, Slack, Notion, anywhere text is typed.

---

## 1. Problem & Goal

Rewriting text with AI today means copy → open ChatGPT → paste → prompt → copy → paste back. That breaks flow. WriterFlow removes all of that: the assistant lives where you type, understands the surrounding context (email thread, chat history), and rewrites in-place in under 2 seconds.

**Goals**
- Zero-friction: never leave the current app; no copy-paste round trips.
- Context-aware: reads the input field content and visible conversation context via macOS Accessibility API.
- Invisible-first: no windows, no dock icon. Only a tiny floating icon while typing, plus a menu bar glyph.
- Smooth: <150 ms icon appearance, streamed AI output, native-feel animations.
- Public and free for v1: no WriterFlow account or sign-in, membership, subscription, payment, or remote user database. Each user supplies an Azure OpenAI endpoint/key and pays their own provider usage.
- Secret-safe: no maintainer-owned AI API key or other long-lived service credential is released in the Mac app or DMG.

**Non-goals (v1)**
- Voice dictation (that's Whisperflow's job — we're the typing counterpart).
- Windows/Linux support.
- Mac App Store distribution (Accessibility APIs used here fail App Store review).
- Apple Developer Program membership, Developer ID signing, notarization, stapling, or Sparkle. These are v2 distribution improvements; v1 is a public DMG containing an ad-hoc-signed app, with a documented Gatekeeper override and manual updates.
- Remote accounts, membership/entitlement storage, billing, licensing, teams, or cross-device user-data sync. Any remote user or membership database is v2-only.
- A bespoke WriterFlow HTTP/REST/GraphQL API. V1 calls the user's Azure OpenAI resource directly with their own Keychain-stored key; static downloads, checksums, and docs are not APIs.

---

## 2. Target User

Primary: macOS users writing emails/messages all day who want confidence in their English phrasing and speed, including Karan's own daily workflow. Persona traits: writes across Gmail, WhatsApp Web/Desktop, Slack, LinkedIn; wants natural, native-sounding output; values speed over configurability. V1 is publicly downloadable and does not require a WriterFlow account or paid membership.

---

## 3. Core User Experience

### 3.1 States

| State | What the user sees |
|---|---|
| Idle | Nothing except a small menu bar icon. App runs in background, launches at login. |
| Typing detected | A ~28 px floating pill icon fades in near the caret / focused field (bottom-right corner of the field). Disappears 4 s after typing stops or on field blur. |
| Icon clicked OR hotkey (default `⌃⌥ Space`) | Action popover opens: Elaborate · Formal · Casual · Fix Grammar · Reply · Custom prompt box. Rendered as a compact non-activating panel so focus never leaves the text field. |
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
3. **Settings** — hotkey, icon behavior (always/on-typing/hotkey-only), production AI-service status, excluded apps list, clipboard-fallback toggle, launch at login. Public builds do not expose shared provider keys or a user-editable service endpoint.
4. **Usage** — action counts, acceptance rate, and token-volume diagnostics. WriterFlow itself is free; this is not a billing surface.

---

## 5. Architecture

**Stack: native Swift (AppKit + SwiftUI).** Chosen over Electron/Tauri because the whole product is deep macOS integration (AX API, non-activating panels, event taps, Keychain); native gives the smoothness requirement for free and idles at ~40 MB RAM.

```
┌────────────────────────── WriterFlow.app (menu bar, LSUIElement) ─────────────────────────┐
│                                                                                           │
│  FocusMonitor          OverlayController          ActionEngine            Dashboard        │
│  (AXObserver on        (NSPanel, non-activating,  (prompt builder +       (SwiftUI window) │
│  focus/typing events)   .floating level, fades     managed AI transport,                   │
│         │               near caret)                streaming)                  │           │
│         ▼                    │                         │                       │           │
│  ContextExtractor ───────────┴────► PreviewCard ◄──────┘                       │           │
│  (AX tree walk, app rules)          (replace/copy/retry)                       │           │
│                                                                                │           │
│  Store: local SQLite (history, memory) · UserDefaults (settings); no remote user DB ┘       │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

**Key components**

- **FocusMonitor:** `AXObserver` for `kAXFocusedUIElementChangedNotification` + a passive CGEventTap (listen-only) to detect keystrokes → drives icon show/hide. Debounced; <1% CPU idle.
- **OverlayController:** non-activating `NSPanel` (`.nonactivatingPanel`, window level `.floating`, ignores mouse until hover) positioned from the focused element's AX frame. This is what makes it "smooth" — focus never leaves the user's field.
- **ActionEngine:** builds prompt = system prompt (voice profile + per-app rule) + context block + user text + action instruction, then streams from the user's Azure OpenAI resource; first token target <800 ms.
- **Model:** the user configures exact Azure deployment names for default/grammar/heavy classes in Setup or Settings. Public v1 makes one provider request per explicit action.
- **Global hotkey:** `⌃⌥ Space` via Carbon `RegisterEventHotKey` (configurable).

**Permissions required:** Accessibility (System Settings → Privacy & Security → Accessibility) and Input Monitoring. Onboarding flow walks through granting both, with live status checks.

---

## 6. Privacy & Security

- No maintainer-owned Azure/OpenAI/provider API key, backend bearer secret, signing credential, `.env`, or `secrets.env` may be included in or persisted by the public app. Keychain does not make a shared key safe to distribute.
- All history/memory remains local (SQLite in `~/Library/Application Support/WriterFlow`). V1 has no remote user, account, membership, entitlement, billing, or sync database.
- V1 exposes no custom WriterFlow API. AI inference uses the user's own Azure OpenAI endpoint, API key (Keychain only), deployments, quota, and billing.
- Per-app exclusion list (e.g., 1Password, banking apps) — AX reads never occur there.
- Secure input fields always ignored.
- One-click "pause WriterFlow" from the menu bar.
- Data sent for AI processing: only on explicit user action (never passive keystroke streaming). The payload may include the selected/field text, visible conversation context, the user's custom instruction, and enabled local personalization. The explicit **Analyze My Writing Style** action may send up to 20 accepted outputs for that one analysis. Keystroke monitoring is used solely as a local "is typing" signal — key contents are not buffered, stored, or sent.

Release builds compile out `.env` / `secrets.env` credential fallback, allow only HTTPS Azure Responses endpoints, and never start recommendation inference from passive typing. See `RELEASE.md`.

---

## 7. Milestones

Development is AI-assisted (Claude Code / Cursor) — phases are ordered by dependency, not calendar time. Detailed breakdowns live in `phases/`. See `ROADMAP.md` for sequencing, `RELEASE.md` for production, and the mirrored `CLAUDE.md` / `AGENTS.md` files for tool context.

| Phase | Scope | Detail file |
|---|---|---|
| **P0 — Skeleton** | Menu bar app, permissions onboarding, FocusMonitor, floating icon shows/hides on typing | `phases/phase-0-foundation.md` |
| **P1 — Core actions** | AX read/replace, popover with Core 4 actions, streaming AI preview (direct Azure development transport originally), hotkey | `phases/phase-1-core-actions.md` |
| **P2 — Context & Reply** | AX tree context extraction, per-app tone defaults, Reply + Custom actions, Chrome/Electron fallbacks | `phases/phase-2-context-reply.md` |
| **P3 — Dashboard & memory** | History, voice profile, per-app rules, usage stats, settings | `phases/phase-3-dashboard-memory.md` |
| **P4 — Polish** | Animations, clipboard fallback, excluded apps, public DMG containing an ad-hoc-signed app, manual Gatekeeper install flow, login item | `phases/phase-4-polish-release.md` |

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
| Mac App Store rejection (private AX usage) | V1 direct DMG distribution with published checksum and documented **Open Anyway** flow; Developer ID/notarization/Sparkle deferred to v2 |
| Unidentified/unnotarized v1 build creates install friction | State the limitation plainly, test on a clean unmanaged Mac, never ask users to disable Gatekeeper; managed Macs may be unsupported |
| Provider credential extraction or anonymous AI abuse | V1 has no shared key: each user's Azure key stays in Keychain, requests are restricted to validated Azure HTTPS endpoints, and the release artifact is secret-scanned |
| AI model retirements | Provider/platform-side routing; a static non-secret client config may supply safe fallbacks, but never credentials or an arbitrary service contract |
| Latency spikes ruin "smooth" feel | Streaming UI, optimistic spinner, nano model for grammar, request timeout + retry |
| Privacy concerns from keystroke monitoring | Listen-only local signal, clear onboarding copy, open pause control |

---

## 10. Open Questions

1. Should Reply mode support multi-language (detect Hindi/Hinglish input, reply in same language)? — likely yes, cheap to add via prompt.
2. Local model fallback (Apple Foundation Models) for offline grammar fixes? — post-v1.
3. V2 commercial/team/licensing model? — resolved at planning level by `PRD-V2.md`:
   Free/Pro first, team-ready ownership schema, and metered overage only after shadow
   usage reconciliation. Exact prices and allowances remain measurement-dependent.

# Phase 1 — Core Actions & AI Engine

> **Production supersession (v1.0):** This file records the completed direct-Azure development implementation. Its `.env`/Keychain/shared-key transport is not approved for the public v1 build. `RELEASE.md` now requires a provider-managed transport with no distributed long-lived secret, explicit-action-only network behavior, and no custom WriterFlow API. Preserve this checklist as implementation history; follow `RELEASE.md` for production.

**Goal:** Click the icon (or press `⌃⌥ Space`) → pick Elaborate / Formal / Casual / Fix Grammar → streamed result → one-key replace in place.

## Stage 1.1 — Text read/write via AX

- [x] `ContextExtractor.readFocusedField(pid:bundleID:)` → `FieldSnapshot { fullText, selectedText, selectedRange, role, appBundleID }` using `AXValue`, `AXSelectedText`, `AXSelectedTextRange`.
- [x] `TextWriter.replace(pid:range:with:)` tiered:
  1. Set `AXSelectedTextRange` then `AXSelectedText` (preserves rich text).
  2. Full `AXValue` overwrite, gated by role `AXTextField / AXTextArea / AXComboBox`.
  3. Clipboard fallback deferred to Phase 4 → returns `.failed`.
- [x] `CompatibilityMap` actor persists per-bundle read/write counters to `~/Library/Application Support/WriterFlow/compatibility.json` (500 ms debounce, atomic write).
- [x] All AX IO on `AXQueue.shared`, 500 ms per-element `AXUIElementSetMessagingTimeout`.

**Accept:** Read + in-place replace works in TextEdit, Notes, Safari-Gmail, Chrome-Gmail, Slack. Undo (`⌘Z`) restores original in at least TextEdit/Notes.

## Stage 1.2 — Action popover UI

- [x] Non-activating panel anchored to the icon: 6 buttons — Elaborate, Formal, Casual, Fix Grammar, Reply (disabled until Phase 2), Custom (disabled until Phase 2).
- [x] Keyboard-first: open with `⌃⌥ Space` (Carbon `RegisterEventHotKey`), navigate with arrows/1–4, Esc closes.
- [x] Global hotkey works even when icon is hidden (acts on currently focused field).
- [x] Popover never takes key focus away from the text field; buttons respond to first click.

**Accept:** Full flow without mouse: type → `⌃⌥ Space` → `2` → result. Caret never leaves Gmail compose.

## Stage 1.3 — Azure OpenAI ActionEngine

- [x] `AzureOpenAIClient`: Azure Responses API (`TARGET_URI` from `.env`), streaming (SSE), deployment per model slot. API key from Keychain (seeded from `.env` on first launch).
- [x] Models config (single source of truth, JSON in `~/Library/Application Support/WriterFlow/models.json`, bootstrapped from `.env`):
  - default: `gpt-5.4-mini` (`AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini`)
  - grammar: `gpt-5.4-mini` (same deployment until nano is provisioned)
  - heavy (optional): `gpt-5.4-pro` (`AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro`)
- [x] Prompt builder:
  ```
  system:  You are a writing assistant... {voice profile placeholder}
           App context: {bundle ID → tone bias}
           Rules: preserve meaning, output ONLY the rewritten text, match input language.
  user:    [ACTION=formal] <selected or full text>
  ```
- [x] Per-action instruction blocks (elaborate / formal / casual / grammar) in `Prompts.swift` — easy to iterate.
- [x] Streaming: 15 s timeout; 1 retry on 5xx/timeout; non-activating error toast on failure.
- [x] Emit `ConversionEvent` (timestamp, app, action, input, output, accepted?) to `conversions.jsonl` — Phase 3 dashboard consumes this.

**Accept:** Each of the 4 actions returns sensible output; grammar action noticeably faster; airplane mode shows a clean error, not a hang.

## Stage 1.4 — Preview card

- [x] Result streams into a card below/above the popover (auto-position within screen).
- [x] Actions: **Replace** (Enter), **Copy** (⌘C), **Retry** (⌘R), **Discard** (Esc).
- [x] Diff hint: subtle highlight of changed words for Fix Grammar (word-level diff via `CollectionDifference` in `WordDiff.swift`).
- [x] After Replace: card shows a 5 s "Restore original" undo chip (uses saved original text). Implemented as `UndoToast.swift`, a dedicated toast rather than extending `ErrorToast` (kept one responsibility per component).
- [x] Mark `ConversionEvent.accepted = true` on Replace/Copy. Deviation: `ActionEngine` no longer appends the event itself — it hands the unpersisted `ConversionEvent` to `OverlayController`, which appends exactly once at each terminal outcome (Replace/Copy → accepted, Discard/Retry/blur → not) via `finalizeEvent(accepted:)`.

**Accept:** Type rough sentence in WhatsApp Desktop → `⌃⌥ Space` → Casual → Enter → text replaced, chat still focused, send with Enter works immediately after.

## Stage 1.5 — Keychain & first-run API key

- [x] Settings pane (stub window ok): paste OpenAI key → validate with a 1-token test call → store in Keychain (`kSecClassGenericPassword`). `AzureOpenAIClient.ping(deployment:apiKeyOverride:)` validates the pasted key directly (without touching the saved key) before `KeychainStore.saveUserProvidedKey` persists it.
- [x] Friendly error states: invalid key, quota exceeded, rate limited. Mapped in `SettingsViewModel.friendlyMessage(for:)` from Azure HTTP status codes (401/403 → invalid key, 429 → rate limited).

**Accept:** Key survives restart; never appears in logs or UserDefaults.

## Exit criteria (whole phase)

Daily-drivable for the Core 4 actions in Gmail, Slack, WhatsApp Desktop, Notes. p50 full-rewrite latency < 2.5 s for 100 words.

# Phase 3 — Dashboard, History & Memory

> **Production supersession (v1.0):** This file records the completed direct-Azure development UI and local data implementation. Local GRDB/SQLite history, memory, snippets, and app rules remain v1. Direct provider key/endpoint/model controls and cost-pricing UI are development-only until the provider-managed production transport in `RELEASE.md` is integrated. Remote user/membership databases remain v2-only.

**Goal:** A dashboard window for history of conversions, personalization/voice memory, per-app rules, settings, and usage stats. Everything local.

## Stage 3.1 — Store

- [x] SQLite via GRDB at `~/Library/Application Support/WriterFlow/writerflow.db` (`WriterFlowDatabase.swift`).
- [x] Tables:
  - `conversions(id, timestamp, appBundleID, site, action, input, output, accepted, model, tokensIn, tokensOut, latencyMs)` — camelCase to match the Swift `ConversionEvent` record directly (GRDB Codable derivation); same fields as the spec's snake_case names.
  - `memory_notes(id, kind[style|fact|snippet], text, enabled, updatedAt)`
  - `app_rules(bundleOrSite, tone, signature, customInstruction, excluded)`
- [x] Migrate Phase 1's `ConversionEvent` logging into this store — `ConversionEventStore.migrateLegacyLogIfNeeded()` backfills `conversions.jsonl` (100 legacy rows verified end-to-end), then renames it to `conversions.jsonl.migrated`. Runs eagerly at launch (`SettingsStore.init`) and is idempotent/safe to also run lazily before the first `append()`.
- [x] Retention setting: keep 30/90/∞ days (`SettingsStore.historyRetention`, `RetentionPeriod` enum) — default **90 days** (confirmed with user 2026-07-14, not specified in this doc). Purge runs at launch and immediately on setting change (live-apply). "Clear history" button itself is Stage 3.2 UI (`ConversionEventStore.deleteAll()` already exposed for it).

## Stage 3.2 — Dashboard shell + History tab

- [x] SwiftUI window from menu bar → tabs: History · Personalization · Settings · Usage (`Dashboard/DashboardView.swift`, `DashboardWindowController.swift`; wired to the existing "Open Dashboard" menu item, previously a stub). All four tabs are now fully real as of Stage 3.4/3.5 below (Personalization/Settings/Usage started as placeholders, since replaced).
- [x] **Launch-flow addendum (2026-07-14, user-requested, not in the original spec):** the Dashboard now opens by default on every launch/reopen, regardless of permission state — it's all local-data screens, no AX/Input Monitoring needed to browse history, edit personalization, change settings, or view usage. Missing permissions still surface the onboarding window on top (floating level), but onboarding is now non-blocking: it links straight back to the Dashboard ("Open Dashboard") instead of gating access to it. See `AppDelegate.applicationDidFinishLaunching`/`applicationShouldHandleReopen`, `OnboardingWindowController.onOpenDashboard`.
- [x] History list: date-grouped rows — app icon (`AppIconResolver.swift`), action chip, before→after preview (`HistoryRowView.swift`); click → detail with side-by-side diff (reuses `WordDiff`), Copy input/output (`HistoryDetailView.swift`).
- [x] Search (full text over input+output) + filters (app, action, accepted) — `HistoryViewModel.swift`.
- [x] Everything reads reactively from GRDB (`ValueObservation.tracking(...).values(in:)` async stream, not the polling/callback API).

**Accept:** Every action performed since Phase 1 shows up; search "deadline" finds the right conversion. — **Visually verified by user 2026-07-14**: Dashboard → History opens and shows past conversions correctly.

## Stage 3.3 — Personalization & memory

- [x] **Voice profile (manual):** editable free-text "About my writing style" + structured fields (name to sign as, role, company, preferred greeting/sign-off) — `Store/VoiceProfile.swift`, persisted via `SettingsStore.voiceProfile` (JSON in UserDefaults; single record, not a list, so no dedicated table). Injected into every system prompt via `MemoryPromptBuilder` → `PromptBuilder.PersonalizationContext`.
- [x] **Voice profile (learned):** ~~background job — after every 20 accepted rewrites, run a cheap model pass~~ **deviation (confirmed with user 2026-07-14):** an automatic background job would violate CLAUDE.md Golden Rule #2 ("text is sent to OpenAI ONLY on explicit user action"). Implemented instead as an explicit **"Analyze my writing style"** button in the Personalization tab (`PersonalizationViewModel.analyzeStyle()` → `AzureOpenAIClient.analyzeWritingStyle()`) — same model pass over the last 20 accepted outputs (`ConversionEventStore.recentAcceptedOutputs`), same propose/approve/reject flow (`proposedStyleText` + Add to Memory/Discard), just user-triggered rather than silently automatic after N accepts. Requires ≥3 accepted actions first.
- [x] **Snippets/facts:** list of facts the model may use (email, calendly link, company boilerplate). Enable/disable per item — `Store/MemoryStore.swift` (reactive GRDB `ValueObservation` CRUD over `memory_notes`), UI in `Dashboard/PersonalizationView.swift`.
- [x] **Per-app rules editor:** table of app/site → tone, signature, extra instruction, exclude toggle — `Store/AppRuleStore.swift`, seeded once from Phase 2's `AppAdapter` tone defaults (gmail/outlook/linkedin/whatsapp/slack/telegram/notion/cursor/terminal). **Known limitation:** the exclude toggle only matches by bundle id, not by site — `FocusedField` doesn't carry `windowTitle` at focus time (only `FieldSnapshot` does, read later), so a browser-hosted site like "gmail" can't be excluded without excluding the whole browser. Tone/signature/instruction overrides (resolved later, in `ActionEngine`, where the site *is* known) correctly match by site first, falling back to bundle id.
- [x] Prompt budget: memory content capped at ~600 tokens (`MemoryPromptBuilder.tokenBudget`, ~4 chars/token estimate); over-budget → oldest-by-`updatedAt`-excluded-first, with a warning banner in the Personalization tab showing the excluded count.

**Accept:** Add "always sign emails as 'Best, Karan'" → next Gmail Formal rewrite includes it. Excluded app (e.g., 1Password) never shows the icon. — **Not yet visually verified**; code builds clean (`swift build`) but this sandbox has no Accessibility/Screen-Recording grant to click through the actual window or trigger a live Gmail rewrite. Pending user confirmation.

## Stage 3.4 — Settings tab

- [x] **Hotkey recorder with real collision validation** — `Store/SettingsStore.swift`'s `HotkeyCombo` (Carbon keycode + modifier bitmask, default ⌃⌥Space unchanged), `Dashboard/HotkeyRecorderView.swift` (click, press combo, Esc to cancel; requires ≥1 modifier so it can't shadow normal typing), `GlobalHotkey.install(combo:)` (now takes any combo, not just the hardcoded default). Collision check is the real OS call (`RegisterEventHotKey`), not a static guess-list — `AppDelegate.applyHotkeyCombo` attempts registration immediately on change, reverts to the last-good combo and surfaces why (`settings.hotkeyStatusMessage`) if another app already owns it.
- [x] **Icon behavior mode** — radio picker over `IconMode` (onTyping/alwaysOnFocus/hotkeyOnly) with a plain-language explanation of each that updates as you pick.
- [x] **Model pickers per action class** — three deployment-name fields (Default/Grammar/Heavy) in `Dashboard/SettingsTabView.swift`, backed by `SettingsTabViewModel` which writes straight to `models.json` via `AzureModelsConfig.save()` on every edit. Live-apply: `AzureOpenAIClient` was changed to re-read `models.json` fresh on every request (`initialConfig` is now just the launch-time fallback) instead of caching the struct passed at init — so a model-name edit applies to the very next action, not just the next app launch.
- [x] **API key management** — inline masked `SecureField` + Validate & Save (reuses `SettingsViewModel`'s existing 1-token ping + Keychain save, just embedded in the tab instead of a separate window). The standalone Phase 1.5 `SettingsWindowController`/`SettingsView` were retired — Dashboard is now the one settings surface (⌘, opens Dashboard).
- [x] **Clipboard-fallback toggle** — `SettingsStore.forceClipboardFallback`; when on, `TextInserter.replace` skips the AX write tiers entirely and always pastes via clipboard.
- [x] Launch at login toggle, retention picker — both already existed as settings/logic from Phase 0/Stage 3.1, this stage just added the UI controls for them.
- [x] All settings live-apply, no restart — verified by construction (every control writes straight to a `@Published`/`didSet` or to disk, with no cached copies left stale) rather than by a runtime click-through in this sandbox.

## Stage 3.5 — Usage tab

- [x] Daily/weekly stacked-bar charts (Swift Charts, `Dashboard/UsageView.swift` + `UsageViewModel.swift`): actions by type (fixed categorical color order matching `WritingAction.allCases`) and token volume (input/output), toggle between "Last 14 Days" and "Last 12 Weeks". Estimated cost pulls from the pricing table added to `AzureModelsConfig` (`$/1M tokens` per deployment, editable indirectly by editing `models.json`; UI editing of the pricing table itself is not yet exposed — only the deployment *name* fields are, in Stage 3.4's Settings tab).
- [x] Acceptance rate metric (accepted / total) — shown as the largest, first stat tile, explicitly called out as the product's north star in the tab's intro copy. Shows "—" (not a misleading 0%) when there's no data yet.

**Both stages' accept criteria — not yet visually verified**: code builds clean (`swift build`), but this sandbox has no Accessibility/Screen-Recording grant to click through the actual window, record a hotkey, or compare Usage numbers against a real OpenAI dashboard. Pending user confirmation.

## Exit criteria

Dashboard opens < 500 ms; memory demonstrably changes output; usage numbers match OpenAI dashboard within ~10%. — Dashboard-opens-fast is now exercised on every launch (see the launch-flow addendum under Stage 3.2); the other two criteria are pending the user's live verification pass.

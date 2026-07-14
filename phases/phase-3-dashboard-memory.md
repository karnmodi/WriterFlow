# Phase 3 — Dashboard, History & Memory

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

- [x] SwiftUI window from menu bar → tabs: History · Personalization · Settings · Usage (`Dashboard/DashboardView.swift`, `DashboardWindowController.swift`; wired to the existing "Open Dashboard" menu item, previously a stub). Personalization and Usage are placeholder tabs pending Stage 3.3/3.5; Settings tab is a placeholder linking to the existing Phase 1.5 API-key window pending Stage 3.4's full settings editor.
- [x] History list: date-grouped rows — app icon (`AppIconResolver.swift`), action chip, before→after preview (`HistoryRowView.swift`); click → detail with side-by-side diff (reuses `WordDiff`), Copy input/output (`HistoryDetailView.swift`).
- [x] Search (full text over input+output) + filters (app, action, accepted) — `HistoryViewModel.swift`.
- [x] Everything reads reactively from GRDB (`ValueObservation.tracking(...).values(in:)` async stream, not the polling/callback API).

**Accept:** Every action performed since Phase 1 shows up; search "deadline" finds the right conversion. — **Not yet visually verified.** Code compiles clean and the underlying store is confirmed working live (a real Custom action logged correctly to `writerflow.db` during this session), but this sandbox has no Accessibility/Screen-Recording grant to click through or screenshot the actual SwiftUI window. Pending user confirmation after opening Dashboard → History from the menu bar.

## Stage 3.3 — Personalization & memory

- [ ] **Voice profile (manual):** editable free-text "About my writing style" + structured fields (name to sign as, role, company, preferred greeting/sign-off). Injected into every system prompt.
- [ ] **Voice profile (learned):** ~~background job — after every 20 accepted rewrites, run a cheap model pass~~ **deviation (confirmed with user 2026-07-14):** an automatic background job would violate CLAUDE.md Golden Rule #2 ("text is sent to OpenAI ONLY on explicit user action"). Implement instead as an explicit **"Analyze my writing style"** button in the Personalization tab — same model pass over recent accepted outputs, same propose/approve/reject flow, just user-triggered rather than silently automatic after N accepts.
- [ ] **Snippets/facts:** list of facts the model may use (email, calendly link, company boilerplate). Enable/disable per item.
- [ ] **Per-app rules editor:** table of app/site → tone, signature, extra instruction, exclude toggle. Seeded from Phase 2 defaults.
- [ ] Prompt budget: memory content capped at ~600 tokens; over-budget → oldest-disabled-first warning.

**Accept:** Add "always sign emails as 'Best, Karan'" → next Gmail Formal rewrite includes it. Excluded app (e.g., 1Password) never shows the icon.

## Stage 3.4 — Settings tab

- [ ] Hotkey recorder (validate collisions), icon behavior mode, model pickers per action class, API key management (masked, re-validate button), clipboard-fallback toggle, launch at login, retention.
- [ ] All settings live-apply, no restart.

## Stage 3.5 — Usage tab

- [ ] Daily/weekly charts (Swift Charts): actions count by type, tokens, estimated cost (pricing table in the models config JSON so it's updatable).
- [ ] Acceptance rate metric (accepted / total) — the product's north star.

## Exit criteria

Dashboard opens < 500 ms; memory demonstrably changes output; usage numbers match OpenAI dashboard within ~10%.

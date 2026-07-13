# Phase 3 — Dashboard, History & Memory

**Goal:** A dashboard window for history of conversions, personalization/voice memory, per-app rules, settings, and usage stats. Everything local.

## Stage 3.1 — Store

- [ ] SQLite via GRDB at `~/Library/Application Support/WriterFlow/writerflow.db`.
- [ ] Tables:
  - `conversions(id, ts, app_bundle, site, action, input, output, accepted, model, tokens_in, tokens_out, latency_ms)`
  - `memory_notes(id, kind[style|fact|snippet], text, enabled, updated_at)`
  - `app_rules(bundle_or_site, tone, signature, custom_instruction, excluded)`
- [ ] Migrate Phase 1's `ConversionEvent` logging into this store (backfill if a temp log exists).
- [ ] Retention setting: keep 30/90/∞ days; "Clear history" button wipes table.

## Stage 3.2 — Dashboard shell + History tab

- [ ] SwiftUI window from menu bar → tabs: History · Personalization · Settings · Usage.
- [ ] History list: date-grouped rows — app icon, action chip, before→after preview; click → detail with side-by-side diff, Copy input/output.
- [ ] Search (full text over input+output) + filters (app, action, accepted).
- [ ] Everything reads reactively from GRDB (ValueObservation).

**Accept:** Every action performed since Phase 1 shows up; search "deadline" finds the right conversion.

## Stage 3.3 — Personalization & memory

- [ ] **Voice profile (manual):** editable free-text "About my writing style" + structured fields (name to sign as, role, company, preferred greeting/sign-off). Injected into every system prompt.
- [ ] **Voice profile (learned):** background job — after every 20 accepted rewrites, run a cheap model pass over recent accepted outputs to propose style notes ("prefers short sentences", "signs off with 'Cheers, Karan'"). Proposals appear as suggestions the user approves/rejects — never silently applied.
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

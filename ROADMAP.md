# WriterFlow — Development Roadmap

Master index for all planning docs. Read `PRD.md` first for product context.

## Docs structure

| File | What's inside |
|---|---|
| `CLAUDE.md` / `AGENTS.md` | Intentional tool-specific mirrors for AI-assisted development; update together |
| `PRD.md` | Product requirements — the *what* and *why* |
| `ROADMAP.md` | This file — phase order, timeline, dependencies |
| `RELEASE.md` | Canonical v1 production gates, packaging runbook, and v1/v2 infrastructure split |
| `phases/phase-0-foundation.md` | Project setup, permissions, focus monitoring, floating icon |
| `phases/phase-1-core-actions.md` | AX read/replace, action popover, streaming AI preview (original direct Azure development transport) |
| `phases/phase-2-context-reply.md` | Conversation context extraction, Reply + Custom, app fallbacks |
| `phases/phase-3-dashboard-memory.md` | Dashboard window, history, voice profile, per-app rules |
| `phases/phase-4-polish-release.md` | Animations, fallbacks, public v1 packaging, manual-install distribution |

## Execution order

Development is AI-assisted (Claude Code / Cursor), so phases are sequenced by dependency, not calendar time. Complete phases strictly in order — each phase's exit criteria must pass before starting the next:

`Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4`

Within a phase, stages (x.1, x.2, …) are also ordered; stages inside a phase may be parallelized only when they don't share components.

## Dependencies

- Phase 1 needs Phase 0's FocusMonitor + OverlayController working.
- Phase 2 needs Phase 1's ActionEngine + replace pipeline.
- Phase 3 needs Phase 1's history events being emitted (log from day one).
- Phase 4 needs everything feature-complete.

## v1.0 production path

`RELEASE.md` is the canonical release runbook. The v1 product and infrastructure
boundary is:

- public and free to download, with no WriterFlow account, membership, subscription,
  payment, or licensing flow; core AI actions require the user's own Azure OpenAI key
  and may incur charges on that user's Azure account;
- local GRDB/SQLite and UserDefaults storage only — no remote user, membership,
  entitlement, billing, or sync database and no AI service credential in public v1;
- no bespoke WriterFlow API;
- direct AI inference through the user's Azure OpenAI Responses endpoint, with no
  publisher-owned/shared reusable service credential in the public Mac app;
- release-mode DMG containing an ad-hoc-signed app, plus SHA-256 checksum, manual
  Gatekeeper **Open Anyway** approval, and manual updates;
- no Apple Developer Program membership requirement for v1.

The BYO Azure path is the approved v1 transport. Passive typing no longer starts
inference, release builds compile out file credential fallbacks, and the release
verifier checks the app and mounted DMG. Live UI/Accessibility validation, the soak,
and clean-Mac Gatekeeper installation evidence remain tag gates.

## v1.0 release definition of done

In addition to the phase criteria below:

1. Anyone on a supported unmanaged Mac can download the app without a WriterFlow
   account or payment and follow the documented Gatekeeper override.
2. No remote user/membership database and no custom WriterFlow API are present.
3. AI uses the user's own Azure endpoint, key, quota, rate limits, and billing without
   any distributed publisher/shared key.
4. Text and context leave the Mac only after explicit user action.
5. The app and mounted DMG contain no `.env`, `secrets.env`, API key, bearer token,
   private endpoint, or signing credential.
6. The published DMG version and CPU support match the release notes, and its SHA-256
   checksum is published and verified on a clean Mac.

## Definition of done (every phase)

1. All acceptance criteria in the phase file pass.
2. Manually tested in the phase's target apps (listed per phase).
3. No regressions in previous phases' criteria.
4. Idle CPU < 1%, no memory growth over a 2-hour session.

## Golden rules

- Never block the main thread — all AX reads and API calls off-main.
- Focus must never leave the user's text field (non-activating panels only).
- No text leaves the machine except on explicit user action.
- Secure fields are invisible to the app, always.

## v1.1 product backlog (not started)

Carried over from `PRD.md` §9 (Risks & Mitigations) and §10 (Open Questions) —
deliberately not attempted during v1:

- **Multi-language Reply polish** — detect Hindi/Hinglish (and other non-English) input
  and reply in the same language/register. PRD's guess is this is cheap to add via
  prompt changes alone once someone dogfoods it in a non-English conversation.
- **Offline grammar via Apple Foundation Models** — a local on-device fallback for Fix
  Grammar when there's no network, instead of just the "you're offline" error Stage 4.3
  added. This would change the current provider-side-only AI policy and therefore needs
  an explicit product-policy decision before implementation, in addition to scope and
  quality evaluation.
- **Windows feasibility spike** — WriterFlow's whole architecture (AX API, CGEventTap,
  NSPanel) is macOS-only. A Windows port would be a from-scratch rebuild on UI
  Automation + a different overlay mechanism, not a port — worth a spike to size before
  committing, not before.

## v2.0 infrastructure deferred from v1

These items are intentionally not v1 blockers:

- Apple Developer Program membership, Developer ID Application signing,
  notarization workflow, ticket stapling, and trusted Gatekeeper identity.
- Sparkle, public appcast hosting, EdDSA update signing, and automatic updates.
- Remote accounts, membership/entitlement records, user-data sync, billing,
  subscriptions, commercial licensing, and team administration.
- A new WriterFlow-operated backend exposed through a bespoke app-facing API. V1 uses
  the provider-platform branch because no existing non-custom WriterFlow transport is
  documented. The no-custom-API rule continues into v2 unless explicitly changed.

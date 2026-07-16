# WriterFlow — Development Roadmap

Master index for all planning docs. Read `PRD.md` first for product context.

## Docs structure

| File | What's inside |
|---|---|
| `CLAUDE.md` | Context file for AI-assisted development (Claude Code / Cursor) — read automatically |
| `PRD.md` | Product requirements — the *what* and *why* |
| `ROADMAP.md` | This file — phase order, timeline, dependencies |
| `phases/phase-0-foundation.md` | Project setup, permissions, focus monitoring, floating icon |
| `phases/phase-1-core-actions.md` | AX read/replace, action popover, OpenAI streaming, preview card |
| `phases/phase-2-context-reply.md` | Conversation context extraction, Reply + Custom, app fallbacks |
| `phases/phase-3-dashboard-memory.md` | Dashboard window, history, voice profile, per-app rules |
| `phases/phase-4-polish-release.md` | Animations, fallbacks, packaging, notarized release |

## Execution order

Development is AI-assisted (Claude Code / Cursor), so phases are sequenced by dependency, not calendar time. Complete phases strictly in order — each phase's exit criteria must pass before starting the next:

`Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4`

Within a phase, stages (x.1, x.2, …) are also ordered; stages inside a phase may be parallelized only when they don't share components.

## Dependencies

- Phase 1 needs Phase 0's FocusMonitor + OverlayController working.
- Phase 2 needs Phase 1's ActionEngine + replace pipeline.
- Phase 3 needs Phase 1's history events being emitted (log from day one).
- Phase 4 needs everything feature-complete.

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

## v1.1 backlog (seeded during Stage 4.5, not started)

Carried over from `PRD.md` §9 (Risks & Mitigations) and §10 (Open Questions) —
deliberately not attempted during v1:

- **Multi-language Reply polish** — detect Hindi/Hinglish (and other non-English) input
  and reply in the same language/register. PRD's guess is this is cheap to add via
  prompt changes alone once someone dogfoods it in a non-English conversation.
- **Offline grammar via Apple Foundation Models** — a local on-device fallback for Fix
  Grammar when there's no network, instead of just the "you're offline" error Stage 4.3
  added. Needs macOS's on-device Foundation Models framework; scope and quality bar
  undecided.
- **Windows feasibility spike** — WriterFlow's whole architecture (AX API, CGEventTap,
  NSPanel) is macOS-only. A Windows port would be a from-scratch rebuild on UI
  Automation + a different overlay mechanism, not a port — worth a spike to size before
  committing, not before.
- **Licensing/team model** — out of scope for v1 per the PRD; revisit only if this
  becomes more than a personal tool.

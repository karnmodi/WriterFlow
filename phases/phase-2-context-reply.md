# Phase 2 — Context Awareness, Reply & Custom

**Goal:** WriterFlow understands *where* you're typing (Gmail thread, WhatsApp chat) and can draft contextual replies or follow free-text instructions.

## Stage 2.1 — App compatibility layer

- [x] `AppAdapter` protocol: `prepare(app:)`, `extractConversation(window:) -> [Message]`, tone bias, quirks.
- [x] Chrome/Chromium: set `AXEnhancedUserInterface = true` on AX app element at first focus; read page title + URL host for site detection (mail.google.com, web.whatsapp.com, linkedin.com).
- [x] Electron apps (Slack, WhatsApp Desktop, Notion): set `AXManualAccessibility = true` via `AXUIElementSetAttributeValue` on the app element.
- [x] Safari: works via standard web AX tree; detect site from window title/AXDocument.
- [x] Generic adapter as fallback: field text only, no conversation context.
- [x] Maintain `compatibility.json`: per-app read/write/context status, shown later in dashboard diagnostics.

**Accept:** Site/app correctly identified for Gmail (Chrome + Safari), WhatsApp (Desktop + web), Slack, Notion, LinkedIn.

## Stage 2.2 — Conversation context extraction

- [x] AX tree walker: from focused field, ascend to window, then breadth-first collect `AXStaticText`/`AXTextArea` nodes that are visible (`kAXFrameAttribute` intersects window bounds), ordered top-to-bottom.
- [x] Heuristics per adapter:
  - Gmail: thread messages are large text blocks above the compose box; capture sender lines.
  - WhatsApp/Slack: chat bubbles — capture last ~20 messages with speaker hint if available.
- [x] Cap: 4,000 chars, keep most recent; strip UI noise (timestamps-only nodes, button labels).
- [x] Performance budget: extraction < 300 ms, off-main, cached for 10 s per window.
- [x] Privacy: context extracted **only when Reply/Custom is invoked** — never passively.

**Accept:** In a real Gmail thread, extracted context contains the last 2 messages' text. In WhatsApp, last several messages. Extraction never beachballs the host app.

## Stage 2.3 — Reply action

- [x] Prompt: system (voice profile + app tone) + `CONVERSATION:` block + `MY DRAFT/INTENT:` (field text, may be empty or rough) + instruction: draft a reply as the user.
- [x] Empty field → generate reply purely from conversation; rough draft → treat as intent ("say I can't make Friday" → polite full reply).
- [x] Output language matches the conversation's language (explicit prompt rule — covers Hindi/Hinglish).
- [x] Uses default model; heavy model if enabled in settings.

**Accept:** In Gmail: receive a meeting request → empty compose → Reply → sensible accept/decline draft referencing the actual email. In WhatsApp: rough "cant come tmrw" → contextual casual message.

## Stage 2.4 — Custom prompt action

- [x] Popover gains a text input row ("Tell WriterFlow what to do…") — Enter runs it.
- [x] Prompt = context (if Reply-style) + field text + user instruction verbatim.
- [x] Last 5 custom instructions shown as quick-repeat chips.

**Accept:** "make this 2 lines and add a deadline of Friday" works on a Gmail draft.

## Stage 2.5 — Per-app tone defaults

- [x] Default map: Gmail/Outlook/LinkedIn → formal bias; WhatsApp/Slack/iMessage → casual bias; unknown → neutral.
- [x] Bias only affects Elaborate/Reply default flavor — explicit Formal/Casual always wins.
- [x] Stored in Store so Phase 3 dashboard can make it user-editable.

## Exit criteria

Reply produces usable drafts (subjectively ≥ 7/10) in Gmail + WhatsApp; context extraction failures degrade gracefully to field-only mode with a small "no context available" note in the preview card.

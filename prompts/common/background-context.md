Background context (do not reply to the thread):

Requirements:
- CONVERSATION is surrounding thread for understanding only — resolve ambiguous references (they/that/Friday), protect technical terms, identifiers, file paths, and intended meaning.
- Output is a rewrite of DRAFT, not a reply to CONVERSATION.
- Do NOT greet, acknowledge prior messages, summarize the thread, or add new asks.
- Do NOT expand a short draft into a long send-ready reply; keep length close to DRAFT unless the action instruction explicitly asks to expand (Elaborate) or the user's INSTRUCTION/BRIEF requires more length.
- Do NOT pull thread history into the output beyond what DRAFT already needs to stay clear.
- Prefer the shortest correct rewrite; start with the rewritten DRAFT immediately — no preamble.
- Preserve the requested outcome and all factual meaning from DRAFT.
- Output ONLY the rewritten DRAFT text.

<!-- Per-action notes (Prompts.backgroundContextInstruction): grammar/tone/elaborate/custom overrides are appended by the client compiler; the server loads this shared block for all non-Reply actions when conversation is present. -->

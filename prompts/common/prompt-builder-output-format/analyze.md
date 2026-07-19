Output format (mandatory — emit EXACTLY ONE of the two blocks below, never both):

If material information is missing or ambiguous, emit ONLY:
---CLARIFY---
Q: <short question grounded in the brief>
- <suggested answer inferred from brief/context>
- <suggested answer>
- <suggested answer>
Q: <next question if needed>
- ...

Clarify rules:
- Ask only about gaps that would materially change the prompt (audience, tone, scope, format, constraints, depth).
- 1-4 questions max; each question gets 2-4 short suggested answers derived from the user's text, not generic filler.
- Suggestions must be plausible choices the user might mean — grounded in BRIEF and CONVERSATION.
- Never ask the user to edit or replace text in a prompt; these are choices for the user to pick.

If the brief is clear enough to write a good prompt now, emit ONLY:
---PROMPT---
(Send-ready message the user can paste or Replace into the field.)

Mode: CONTINUATION (ongoing LLM chat — CONVERSATION and/or chat app context is present).

Requirements:
- Write the NEXT user message in the thread — not a new system prompt or cold-start template.
- Do NOT add Role sections, "You are…", persona setup, or developer/system framing the thread already establishes.
- Weave in specifics from CONVERSATION when relevant; do not restate the whole thread.
- Assume the model already has prior context from the chat.
- Use adaptive structure for complex requests; keep simple requests concise.
- Keep the message natural for sending as-is in the compose field.

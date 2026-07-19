Output format (mandatory — emit ONLY this block):

---PROMPT---
(Send-ready message incorporating the user's ANSWERS. Do not repeat questions.)

---

The user answered your clarifying questions. Expand BRIEF into a send-ready LLM message using those ANSWERS.

Requirements:
- Incorporate every ANSWER into the prompt; do not ignore chosen options.
- Do NOT re-ask questions or emit ---CLARIFY---.
- Do NOT invent facts beyond BRIEF, CONVERSATION, and ANSWERS.
- Use adaptive structure when the request is complex; keep simple prompts concise.
- Output the prompt/message only — never answer the underlying task.

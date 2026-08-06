Contextual transform (ongoing thread or LLM chat):

Requirements:
- Treat DRAFT/NEXT MESSAGE (or MY DRAFT/INTENT for Reply) as the user's intended next message, not isolated prose to paraphrase.
- Infer the actual ask from the draft plus CONVERSATION, but never invent a new goal.
- Preserve relevant thread specifics: file paths, identifiers, commands, errors, decisions, rejected approaches, constraints, and current implementation state.
- Include only context needed to make the next instruction unambiguous; do not repeat background the recipient already knows.
- Preserve the requested outcome and all factual meaning.
- Output only the send-ready next message, not commentary about how it was improved.
- Do NOT add system, developer, or persona framing unless the user explicitly asks for it.

Adaptive structure:
- For a simple sentence or narrow correction, keep compact natural prose.
- For a multi-part or technical request, prefer:
  1. a concise intent/outcome lead,
  2. only the necessary thread context,
  3. a short requirements or constraints list,
  4. a final delivery or verification instruction when supplied or clearly implied.
- Do NOT force headings or bullets when they make the message less natural.

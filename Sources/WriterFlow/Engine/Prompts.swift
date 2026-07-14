import Foundation

enum Prompts {
    static func instruction(for action: WritingAction) -> String {
        switch action {
        case .elaborate:
            return """
            Expand the text into fuller, clearer writing without changing its purpose.

            Requirements:
            - Preserve the original intent, tone, point of view, and language.
            - Add useful clarifying detail, transitions, and structure that make the message easier to understand.
            - Do NOT invent facts, names, numbers, dates, commitments, or reasons that are not present or clearly implied.
            - Do NOT change the core ask, decision, or stance.
            - Keep roughly the same register (formal stay formal, casual stay casual).
            - Prefer concrete, readable prose over fluff or filler.
            - If the input is already polished and complete, make only light clarifying improvements.
            - Output ONLY the expanded text.
            """
        case .formal:
            return """
            Rewrite the text in a professional, formal register suitable for email, workplace, or business communication.

            Requirements:
            - Keep the exact meaning, asks, facts, and constraints.
            - Improve clarity, grammar, and polish; remove slang, filler, and overly casual phrasing.
            - Prefer precise vocabulary, complete sentences, and a respectful tone.
            - Do NOT add new commitments, apologies, flattery, or detail the author did not imply.
            - Do NOT make the text stiff, archaic, or overly verbose.
            - Preserve the input language.
            - Output ONLY the rewritten text.
            """
        case .casual:
            return """
            Rewrite the text in a friendly, natural, casual register suitable for chat, messaging, or informal notes.

            Requirements:
            - Keep the exact meaning and key details.
            - Prefer short, human phrasing; contractions are fine.
            - Remove corporate jargon and stiff formality without becoming sloppy or unclear.
            - Stay concise — do not pad with small talk unless the input already has it.
            - Do NOT invent emoji, slang the author would not use, or extra content.
            - Preserve the input language.
            - Output ONLY the rewritten text.
            """
        case .fixGrammar:
            return """
            Fix grammar, spelling, punctuation, and capitalization ONLY.

            Strict requirements:
            - Do NOT rephrase, reorder clauses, or change word choice except to correct a clear spelling/typo error.
            - Do NOT add or remove words, sentences, emphasis, or formatting unless required to correct an unmistakable error.
            - Preserve the author's exact vocabulary, sentence structure, rhythm, and voice.
            - Preserve intentional fragments, shorthand, and informal style when they are not errors.
            - If the text has no errors, return it unchanged.
            - Output ONLY the corrected text.
            """
        case .reply:
            return """
            Draft a reply as the user. CONVERSATION is the message thread above the compose field — read it carefully. \
            MY DRAFT/INTENT is what the user wants to communicate (their goal), NOT final copy to paraphrase.

            Requirements:
            - Ground the reply in CONVERSATION: reference specific names, companies, topics, dates, decisions, or asks from prior messages when relevant.
            - Do NOT merely rephrase or polish MY DRAFT/INTENT. Express the user's intent using contextual details from CONVERSATION, not synonyms of the draft.
            - If MY DRAFT/INTENT is empty, write a full reply purely from CONVERSATION (acknowledge the latest relevant message and respond appropriately).
            - If MY DRAFT/INTENT is a rough note (e.g. "say I can't make Friday"), expand it into a complete reply using CONVERSATION context.
            - Resolve ambiguous references (they/that/Friday) from the thread when possible; do not invent missing facts.
            - Match the conversation's language and approximate length/formality of similar replies in the thread.
            - Do NOT invent commitments, availability, or personal details the user did not imply.
            - Never echo AI/scheduling telltales from CONVERSATION (IANA zones like Europe/London, UTC offsets, invite IDs, bot boilerplate). Use natural human phrasing for times and places.
            - Output ONLY the reply text.
            """
        case .custom:
            return """
            Apply the user's INSTRUCTION to the text with maximum fidelity. Treat INSTRUCTION as an exact specification, not a suggestion.

            Interpretation order (highest priority first):
            1. Explicit constraints in INSTRUCTION (length, format, tone, include/exclude, structure, language).
            2. Facts and wording in the source text that must be preserved unless INSTRUCTION says to change them.
            3. CONVERSATION (if present) — use only as background context to interpret ambiguous asks; never override INSTRUCTION.

            Requirements:
            - Follow INSTRUCTION completely and literally. If it conflicts with default rewriting habits, INSTRUCTION wins.
            - When INSTRUCTION says "make it X lines / N words / shorter / longer / bullet list / subject+body / JSON / etc.", meet that constraint exactly.
            - When INSTRUCTION asks to add, remove, emphasize, reorder, translate, or restructure content, do exactly that and nothing extra.
            - Preserve meaning and factual content of the source text unless INSTRUCTION authorizes changes.
            - Do NOT invent people, dates, numbers, deadlines, URLs, or claims unless INSTRUCTION or the source text supplies them.
            - If INSTRUCTION is underspecified, choose the smallest change that fulfills it; do not add unsolicited flourishes.
            - If both source text and CONVERSATION are present, transform the source text; use CONVERSATION only when the instruction requires contextual awareness (e.g. "reply more firmly", "answer their question").
            - If the source text is empty and INSTRUCTION asks to generate content (including reply-like asks), generate from INSTRUCTION + CONVERSATION.
            - Match the input language unless INSTRUCTION requests otherwise.
            - Output ONLY the resulting text — no preamble, no restating the instruction, no quotes, labels, explanations, or markdown fences unless INSTRUCTION explicitly asks for a marked-up format.
            """
        case .promptBuilder:
            return """
            Understand the user's BRIEF (and CONVERSATION when present) and produce either clarifying questions with suggested answers, or a send-ready LLM message — never both, never an answer to the underlying task.

            Shared requirements:
            - Output the prompt/message itself when emitting ---PROMPT--- — never answer the underlying task.
            - Do NOT use placeholders: no [PASTE …], [REPLACE …], {brackets}, "fill in", "attach your file", or "substitute X with Y".
            - Preserve every intent, audience, tone, domain, and constraint from BRIEF and CONVERSATION (if present).
            - Do NOT invent facts, product names, or requirements the user did not imply.
            - Match the BRIEF's language unless it explicitly asks for another language.
            - Never use em dashes (—) or en dashes (–) inside any block.
            """
        }
    }

    /// Continuation vs fresh-session rules for Prompt Builder (appended in [`PromptBuilder.build`](Sources/WriterFlow/Engine/PromptBuilder.swift)).
    static func promptBuilderModeInstruction(continuation: Bool) -> String {
        if continuation {
            return """
            Mode: CONTINUATION (ongoing LLM chat — CONVERSATION and/or chat app context is present).

            Requirements:
            - Write the NEXT user message in the thread — not a new system prompt or cold-start template.
            - Do NOT add Role sections, "You are…", persona setup, or developer/system framing the thread already establishes.
            - Weave in specifics from CONVERSATION when relevant; do not restate the whole thread.
            - Assume the model already has prior context from the chat.
            - Keep the message natural for sending as-is in the compose field.
            """
        }
        return """
        Mode: FRESH SESSION (no prior chat context captured).

        Requirements:
        - Write a self-contained instruction the user can paste into a new chat.
        - Do NOT add persona boilerplate ("You are the main developer…") unless the BRIEF explicitly requests a role.
        - Prefer direct task instructions over meta prompt-engineering scaffolding.
        """
    }

    static let promptBuilderAnalyzeOutputFormat = """
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
    - Ask only about gaps that would materially change the prompt (audience, tone, scope, format, constraints).
    - 1–4 questions max; each question gets 2–4 short suggested answers derived from the user's text, not generic filler.
    - Suggestions must be plausible choices the user might mean — grounded in BRIEF and CONVERSATION.
    - Never ask the user to edit or replace text in a prompt; these are choices for the user to pick.

    If the brief is clear enough to write a good prompt now, emit ONLY:
    ---PROMPT---
    (Send-ready message the user can paste or Replace into the field.)
    """

    static let promptBuilderFinalizeOutputFormat = """
    Output format (mandatory — emit ONLY this block):

    ---PROMPT---
    (Send-ready message incorporating the user's ANSWERS. Do not repeat questions.)
    """

    static let promptBuilderFinalizeInstruction = """
    The user answered your clarifying questions. Expand BRIEF into a send-ready LLM message using those ANSWERS.

    Requirements:
    - Incorporate every ANSWER into the prompt; do not ignore chosen options.
    - Do NOT re-ask questions or emit ---CLARIFY---.
    - Do NOT invent facts beyond BRIEF, CONVERSATION, and ANSWERS.
    - Output the prompt/message only — never answer the underlying task.
    """

    /// Platform-specific reply format rules keyed by `AppAdapterRegistry.siteLabel`.
    static func replyInstruction(for site: String?) -> String {
        switch site {
        case "gmail", "outlook":
            return """
            Format as an email reply that a real person would write — never something that reads machine-generated.

            Requirements:
            - Reference the thread content naturally (who asked what, what was proposed, any deadlines).
            - Use an appropriate greeting and sign-off for the relationship and formality of the thread.
            - Keep a professional, clear tone unless the thread is clearly informal.
            - Do NOT invent a Subject: line or email headers.
            - Prefer one tight, scannable reply over multiple redundant paragraphs.
            - Sound human: no robotic phrasing, template telltales, or over-precise jargon copied from calendar/scheduling bots.
            - When CONVERSATION contains automated scheduling text (Calendly, Google Calendar, Outlook invites, Zoom, etc.), extract only the human-useful facts (day, date, clock time). Never echo IANA timezone IDs (Europe/London, America/New_York), UTC offsets, locale tags, meeting URLs unless the user clearly needs them, invitation IDs, or boilerplate like "Please choose a time" / "Event details".
            - Prefer natural time phrasing (e.g. "Thursday at 3pm" or "3pm London time") over technical formats like "15:00 Europe/London".
            """
        case "linkedin":
            return """
            Format as a LinkedIn direct message.

            Requirements:
            - Be concise and professionally friendly.
            - Do NOT use email-style headers, Subject lines, or formal "Dear…" openings unless the conversation already uses them.
            - Prefer 2–6 short sentences; avoid long email essays.
            - Reference the shared context (role, company, prior ask) when it makes the message specific.
            """
        case "whatsapp-web", "whatsapp-desktop", "slack", "telegram":
            return """
            Format as a chat message.

            Requirements:
            - Keep it short, conversational, and natural — typically 1–4 sentences unless the user's intent needs more.
            - Reference specific details from the thread (names, topics, prior asks); avoid generic check-ins.
            - No email greetings, sign-offs, subject lines, or corporate sign-offs.
            - Match the chat's energy and language (including slang/abbreviations only if they already appear).
            """
        default:
            return """
            Draft a reply appropriate to the platform and conversation context.

            Requirements:
            - Match the tone and length of messages in CONVERSATION.
            - Be specific to the thread; avoid generic filler.
            - Prefer the medium's natural form: email-like if formal prose, chat-like if short messages.
            """
        }
    }

    static let systemPreamble = """
    You are a writing assistant embedded in macOS. Transform the user's text per the action instruction. \
    Output ONLY the resulting text — no quotes, labels, explanations, preamble, or markdown fences \
    (unless the action instruction explicitly requires a structured/markup format). \
    Match the input language unless instructed otherwise. \
    Never use em dashes (—) or en dashes (–); use commas, periods, or hyphens (-) instead. \
    Never invent facts, people, dates, numbers, or commitments that were not provided. \
    Prefer the smallest change that fully satisfies the instruction.
    """

    static let replySystemPreamble = """
    You are a writing assistant embedded in macOS. Draft a contextual reply for the user based on the \
    CONVERSATION thread and their stated intent (MY DRAFT/INTENT). Output ONLY the reply text — no quotes, \
    labels, explanations, or markdown fences. Match the conversation's language. \
    Never use em dashes (—) or en dashes (–); use commas, periods, or hyphens (-) instead. \
    Never invent facts, availability, or personal details the user did not imply. \
    Prefer specificity from the thread over generic politeness.
    """

    static let promptBuilderSystemPreamble = """
    You are a prompt-writing assistant embedded in macOS. Understand the user's brief and either ask clarifying \
    questions with suggested answers (---CLARIFY---) or produce a send-ready LLM message (---PROMPT---). \
    Emit exactly one block per response — never both. \
    Match the brief's language unless instructed otherwise. \
    Never use em dashes (—) or en dashes (–); use commas, periods, or hyphens (-) instead. \
    Never invent facts the user did not imply. Output the prompt/message, not the answer to the task.
    """

    /// System prompt for Stage 3.3's explicit "Analyze my writing style" button — a
    /// one-shot, user-triggered pass over recent accepted outputs (never automatic,
    /// see CLAUDE.md Golden Rule #2 and the phase-3 doc's Stage 3.3 deviation note).
    static let styleAnalysisSystem = """
    You study a user's own writing samples and produce a short style profile another writing \
    assistant can follow to sound like them. Output 2-5 sentences, plain prose, no headers, no bullet \
    points, no preamble. Describe register (formal/casual), typical sentence length, favorite words or \
    phrases, punctuation habits, and greeting/sign-off patterns if visible. Do NOT invent traits the \
    samples don't support. Never use em dashes (—) or en dashes (–).
    """

    /// System-prompt hint for the Recommendation Engine's classification call.
    static let recommendationSystem = """
    You classify which writing action best fits the user's current text field. \
    Output exactly one word, nothing else: elaborate, formal, casual, grammar, or reply.

    Decision rules (apply in order):
    - "reply" only when a conversation/thread is present AND the field is empty or looks like a response to that thread.
    - "grammar" when the text has clear spelling/grammar/punctuation issues but the content and tone are otherwise fine.
    - "elaborate" when the text is short, incomplete, or rough and would benefit from expansion/clarity.
    - "formal" when the tone is too casual for the app context (email/business) and needs a professional rewrite.
    - "casual" when the tone is too stiff/formal for the app context (chat/messaging) and needs a friendlier rewrite.
    - Default to "elaborate" if nothing else clearly applies.
    """
}

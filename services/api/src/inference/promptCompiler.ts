import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { WritingAction } from "@writerflow/shared";
import type { InferenceProviderRequest } from "./provider.js";

const DEFAULT_PROMPTS_DIR = join(process.cwd(), "prompts");

/** Loads a versioned intent prompt from prompts/intents/{name}.md */
export function loadIntentPrompt(intent: string, promptsDir = process.env["PROMPTS_DIR"] ?? DEFAULT_PROMPTS_DIR): string {
  const path = join(promptsDir, "intents", `${intent}.md`);
  return readFileSync(path, "utf8").trim();
}

function loadPrompt(path: string, promptsDir: string): string {
  return readFileSync(join(promptsDir, path), "utf8")
    // HTML comments are prompt-authoring notes, never model instructions.
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim();
}

const intentFiles = {
  elaborate: "elaborate",
  formal: "formal",
  casual: "casual",
  fixGrammar: "grammar",
  reply: "reply",
  custom: "custom",
  promptBuilder: "prompt-builder"
} as const;

/**
 * Character budget for CONVERSATION. Reply/Prompt Builder keep a fuller
 * thread; rewrite actions only need recent context for reference resolution
 * so first-token latency stays in the 1–2s band.
 */
export function conversationBudget(action: WritingAction): number {
  switch (action) {
    case "reply":
    case "promptBuilder":
      return 4_000;
    case "custom":
      return 2_000;
    default:
      return 1_200;
  }
}

/** Keeps the most recent conversationBudget characters (thread tail). */
export function trimConversation(
  action: WritingAction,
  conversation: string | null | undefined
): string | undefined {
  if (conversation == null) return undefined;
  const trimmed = conversation.trim();
  if (!trimmed) return undefined;
  const budget = conversationBudget(action);
  return trimmed.length > budget ? trimmed.slice(-budget) : trimmed;
}

/**
 * Reply gets contextual-transform (draft a thread reply).
 * All other actions with conversation get background-context only
 * (understand the thread; rewrite DRAFT without expanding into a reply).
 */
function conversationPolicyPath(action: InferenceProviderRequest["action"]): string {
  return action === "reply" ? "common/contextual-transform.md" : "common/background-context.md";
}

const llmChatSites = new Set(["chatgpt", "claude", "gemini", "copilot", "perplexity", "poe"]);

/**
 * Closed server mapping: an untrusted client site value can select only one
 * reviewed asset and can never become a filesystem path.
 */
function continuationSitePromptPath(site: string | null | undefined): string {
  if (site === "cursor") return "common/continuation-site/cursor.md";
  if (site && llmChatSites.has(site)) return "common/continuation-site/llm-chat.md";
  return "common/continuation-site/default.md";
}

/** Compile reviewed policy separately from explicit and untrusted request content. */
export function compilePrompt(
  request: InferenceProviderRequest,
  promptsDir = process.env["PROMPTS_DIR"] ?? DEFAULT_PROMPTS_DIR
): { system: string; user: string } {
  const { action, envelope } = request;
  const conversation = trimConversation(action, envelope.content.conversation);
  const preamble =
    action === "reply"
      ? loadPrompt("common/reply-system-preamble.md", promptsDir)
      : action === "promptBuilder"
        ? loadPrompt("common/prompt-builder-system-preamble.md", promptsDir)
        : loadPrompt("common/system-preamble.md", promptsDir);
  const sections = [preamble, loadIntentPrompt(intentFiles[action], promptsDir)];

  if (conversation) {
    sections.push(loadPrompt(conversationPolicyPath(action), promptsDir));
    if (action === "reply") {
      sections.push(loadPrompt(continuationSitePromptPath(envelope.target.site), promptsDir));
    }
  }

  const userParts: string[] = [];
  if (envelope.task.customInstruction) {
    userParts.push(`INSTRUCTION:\n${envelope.task.customInstruction}`);
  }
  if (envelope.task.promptBuilder) {
    const task = envelope.task.promptBuilder;
    userParts.push(`PROMPT BUILDER PHASE: ${task.phase}`);
    if (task.brief) userParts.push(`BRIEF:\n${task.brief}`);
    if (task.answers?.length) userParts.push(`ANSWERS:\n${task.answers.join("\n")}`);
  }
  if (conversation) {
    userParts.push(`CONVERSATION:\n${conversation}`);
  }
  if (envelope.content.selectedText) {
    userParts.push(`SELECTED TEXT:\n${envelope.content.selectedText}`);
  }
  userParts.push(`${action === "reply" ? "MY DRAFT/INTENT" : "DRAFT"}:\n${envelope.content.draft}`);

  return { system: sections.join("\n\n"), user: userParts.join("\n\n") };
}

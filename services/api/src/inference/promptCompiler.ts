import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { InferenceProviderRequest } from "./provider.js";

const DEFAULT_PROMPTS_DIR = join(process.cwd(), "prompts");

/** Loads a versioned intent prompt from prompts/intents/{name}.md */
export function loadIntentPrompt(intent: string, promptsDir = process.env["PROMPTS_DIR"] ?? DEFAULT_PROMPTS_DIR): string {
  const path = join(promptsDir, "intents", `${intent}.md`);
  return readFileSync(path, "utf8").trim();
}

function loadPrompt(path: string, promptsDir: string): string {
  return readFileSync(join(promptsDir, path), "utf8").trim();
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

/** Compile reviewed policy separately from explicit and untrusted request content. */
export function compilePrompt(
  request: InferenceProviderRequest,
  promptsDir = process.env["PROMPTS_DIR"] ?? DEFAULT_PROMPTS_DIR
): { system: string; user: string } {
  const { action, envelope } = request;
  const preamble =
    action === "reply"
      ? loadPrompt("common/reply-system-preamble.md", promptsDir)
      : action === "promptBuilder"
        ? loadPrompt("common/prompt-builder-system-preamble.md", promptsDir)
        : loadPrompt("common/system-preamble.md", promptsDir);
  const sections = [preamble, loadIntentPrompt(intentFiles[action], promptsDir)];

  if (envelope.content.conversation) {
    sections.push(loadPrompt("common/contextual-transform.md", promptsDir));
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
  if (envelope.content.conversation) {
    userParts.push(`CONVERSATION:\n${envelope.content.conversation}`);
  }
  if (envelope.content.selectedText) {
    userParts.push(`SELECTED TEXT:\n${envelope.content.selectedText}`);
  }
  userParts.push(`${action === "reply" ? "MY DRAFT/INTENT" : "DRAFT"}:\n${envelope.content.draft}`);

  return { system: sections.join("\n\n"), user: userParts.join("\n\n") };
}

import type {
  AppTone,
  DecisionIntent,
  InferenceRequestEnvelope,
  LogicalRoute,
  OutputModeHint,
  WritingAction
} from "@writerflow/shared";

export type PromptAppCategory =
  | "email"
  | "chat"
  | "linkedin"
  | "llm_chat"
  | "coding_chat"
  | "other";

export type PromptSourceScope = "selection" | "draft";
export type PromptBuilderMode = "fresh" | "continuation";

export interface PromptPlan {
  action: WritingAction;
  intent: DecisionIntent;
  outputMode: OutputModeHint;
  sourceScope: PromptSourceScope;
  source: string;
  tone: AppTone | null;
  appCategory: PromptAppCategory;
  includeConversation: boolean;
  includePersonalization: boolean;
  promptVariantPaths: readonly string[];
  route: LogicalRoute;
  promptVersion: string;
  promptBuilderMode: PromptBuilderMode | null;
  promptBuilderPhase: "analyze" | "finalize" | null;
}

const emailSites = new Set(["gmail", "outlook", "mail.google.com"]);
const chatSites = new Set(["slack", "whatsapp-web", "whatsapp-desktop", "telegram"]);
const linkedinSites = new Set(["linkedin", "linkedin.com"]);
const llmChatSites = new Set(["chatgpt", "claude", "gemini", "copilot", "perplexity", "poe"]);

export function resolveAppCategory(site: string | null | undefined): PromptAppCategory {
  const normalized = site?.trim().toLowerCase();
  if (!normalized) return "other";
  if (emailSites.has(normalized)) return "email";
  if (chatSites.has(normalized)) return "chat";
  if (linkedinSites.has(normalized)) return "linkedin";
  if (llmChatSites.has(normalized)) return "llm_chat";
  if (normalized === "cursor") return "coding_chat";
  return "other";
}

export function resolveSource(envelope: InferenceRequestEnvelope): {
  source: string;
  sourceScope: PromptSourceScope;
} {
  const selected = envelope.content.selectedText;
  if (
    envelope.content.targetScope === "selection"
    && selected != null
    && selected.trim().length > 0
  ) {
    return { source: selected, sourceScope: "selection" };
  }
  return { source: envelope.content.draft, sourceScope: "draft" };
}

export function resolveTone(action: WritingAction, appTone: AppTone | null | undefined): AppTone | null {
  if (action === "formal") return "formal";
  if (action === "casual") return "casual";
  return appTone ?? null;
}

export const actionIntents: Readonly<Record<WritingAction, DecisionIntent>> = {
  elaborate: "elaborate",
  formal: "tone",
  casual: "tone",
  fixGrammar: "grammar",
  reply: "reply",
  custom: "custom",
  promptBuilder: "prompt_enhance"
};

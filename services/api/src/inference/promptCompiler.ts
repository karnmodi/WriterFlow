import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { load as loadYaml } from "js-yaml";
import { z } from "zod";
import type { WritingAction } from "@writerflow/shared";
import type { InferenceProviderRequest } from "./provider.js";
import {
  actionIntents,
  resolveAppCategory,
  resolveSource,
  resolveTone,
  type PromptAppCategory,
  type PromptPlan
} from "./promptPlan.js";

function defaultPromptsDir(): string {
  const candidates = [
    process.env["PROMPTS_DIR"],
    path.join(process.cwd(), "prompts"),
    path.join(process.cwd(), "..", "..", "prompts")
  ].filter((candidate): candidate is string => Boolean(candidate));
  const found = candidates.find((candidate) => existsSync(path.join(candidate, "manifest.yaml")));
  return found ?? candidates[0] ?? path.join(process.cwd(), "prompts");
}

const AssetSchema = z.strictObject({ path: z.string().min(1) });
const IntentAssetSchema = z.looseObject({
  path: z.string().min(1),
  promptVersion: z.string().min(1)
});
const VariantMapSchema = z.strictObject({
  email: AssetSchema,
  chat: AssetSchema,
  linkedin: AssetSchema,
  llmChat: AssetSchema,
  codingChat: AssetSchema,
  default: AssetSchema
});
const PromptManifestSchema = z.strictObject({
  version: z.string().min(1),
  trustClasses: z.record(z.string(), z.string()),
  systemPreambles: z.strictObject({
    default: z.looseObject({ path: z.string().min(1) }),
    reply: z.looseObject({ path: z.string().min(1) }),
    promptBuilder: z.looseObject({ path: z.string().min(1) }),
    styleAnalysis: z.looseObject({ path: z.string().min(1) })
  }),
  intents: z.strictObject({
    elaborate: IntentAssetSchema,
    formal: IntentAssetSchema,
    casual: IntentAssetSchema,
    fixGrammar: IntentAssetSchema,
    reply: IntentAssetSchema,
    custom: IntentAssetSchema,
    promptBuilder: IntentAssetSchema
  }),
  shared: z.looseObject({
    contextualTransform: z.string().min(1),
    backgroundContext: z.string().min(1),
    untrustedDataPolicy: z.string().min(1)
  }),
  variants: z.strictObject({
    reply: VariantMapSchema,
    promptBuilderMode: z.strictObject({
      fresh: AssetSchema,
      continuation: AssetSchema
    }),
    promptBuilderOutput: z.strictObject({
      analyze: AssetSchema,
      finalize: AssetSchema
    })
  }),
  schemas: z.record(z.string(), z.unknown()),
  evals: z.record(z.string(), z.unknown())
});

type PromptManifest = z.infer<typeof PromptManifestSchema>;

export interface CompiledPrompt {
  plan: PromptPlan;
  system: string;
  user: string;
}

const intentKeys: Readonly<Record<WritingAction, keyof PromptManifest["intents"]>> = {
  elaborate: "elaborate",
  formal: "formal",
  casual: "casual",
  fixGrammar: "fixGrammar",
  reply: "reply",
  custom: "custom",
  promptBuilder: "promptBuilder"
};

/** Character budgets remain part of the frozen Mac/API compatibility contract. */
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

/** Keeps the most recent action-specific number of conversation characters. */
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

function assertSafeAssetPath(promptsDir: string, assetPath: string): string {
  const resolvedRoot = path.resolve(promptsDir);
  const resolved = path.resolve(resolvedRoot, assetPath);
  const relative = path.relative(resolvedRoot, resolved);
  if (
    relative.startsWith("..")
    || path.isAbsolute(relative)
    || path.extname(resolved).toLowerCase() !== ".md"
  ) {
    throw new Error(`Prompt manifest contains an unsafe asset path: ${assetPath}`);
  }
  return resolved;
}

function readPromptAsset(promptsDir: string, assetPath: string): string {
  const contents = readFileSync(assertSafeAssetPath(promptsDir, assetPath), "utf8")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim();
  if (!contents) throw new Error(`Prompt asset is empty: ${assetPath}`);
  return contents;
}

function declaredAssetPaths(manifest: PromptManifest): string[] {
  const paths = [
    ...Object.values(manifest.systemPreambles).map((entry) => entry.path),
    ...Object.values(manifest.intents).map((entry) => entry.path),
    manifest.shared.contextualTransform,
    manifest.shared.backgroundContext,
    manifest.shared.untrustedDataPolicy,
    ...Object.values(manifest.variants.reply).map((entry) => entry.path),
    ...Object.values(manifest.variants.promptBuilderMode).map((entry) => entry.path),
    ...Object.values(manifest.variants.promptBuilderOutput).map((entry) => entry.path)
  ];
  return [...new Set(paths)];
}

function replyVariantPath(manifest: PromptManifest, category: PromptAppCategory): string {
  switch (category) {
    case "email":
      return manifest.variants.reply.email.path;
    case "chat":
      return manifest.variants.reply.chat.path;
    case "linkedin":
      return manifest.variants.reply.linkedin.path;
    case "llm_chat":
      return manifest.variants.reply.llmChat.path;
    case "coding_chat":
      return manifest.variants.reply.codingChat.path;
    case "other":
      return manifest.variants.reply.default.path;
  }
}

function block(name: string, value: string): string {
  const encoded = JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026");
  return `<${name} encoding="json-string">\n${encoded}\n</${name}>`;
}

export class PromptCompiler {
  readonly manifestVersion: string;
  private readonly manifest: PromptManifest;
  private readonly assets: ReadonlyMap<string, string>;

  private constructor(manifest: PromptManifest, assets: ReadonlyMap<string, string>) {
    this.manifest = manifest;
    this.manifestVersion = manifest.version;
    this.assets = assets;
  }

  /** Reads, validates, and caches every declared asset exactly once. */
  static load(promptsDir = defaultPromptsDir()): PromptCompiler {
    const manifestPath = path.join(promptsDir, "manifest.yaml");
    const parsed = PromptManifestSchema.parse(loadYaml(readFileSync(manifestPath, "utf8")));
    const assets = new Map<string, string>();
    for (const assetPath of declaredAssetPaths(parsed)) {
      assets.set(assetPath, readPromptAsset(promptsDir, assetPath));
    }
    return new PromptCompiler(parsed, assets);
  }

  private asset(assetPath: string): string {
    const value = this.assets.get(assetPath);
    if (!value) throw new Error(`Prompt asset was not loaded: ${assetPath}`);
    return value;
  }

  promptVersion(action: WritingAction): string {
    return this.manifest.intents[intentKeys[action]].promptVersion;
  }

  buildPlan(request: InferenceProviderRequest): PromptPlan {
    const { action, envelope } = request;
    const conversation = trimConversation(action, envelope.content.conversation);
    const appCategory = resolveAppCategory(envelope.target.site);
    const source = resolveSource(envelope);
    const promptBuilderPhase = envelope.task.promptBuilder?.phase ?? null;
    const promptBuilderMode = action === "promptBuilder"
      ? conversation || appCategory === "llm_chat" || appCategory === "coding_chat"
        ? "continuation"
        : "fresh"
      : null;
    const variants: string[] = [];

    if (action === "reply") {
      variants.push(replyVariantPath(this.manifest, appCategory));
    }
    if (action === "promptBuilder" && promptBuilderMode && promptBuilderPhase) {
      variants.push(this.manifest.variants.promptBuilderMode[promptBuilderMode].path);
      variants.push(this.manifest.variants.promptBuilderOutput[promptBuilderPhase].path);
    }

    return {
      action,
      intent: actionIntents[action],
      outputMode: envelope.task.outputModeHint,
      sourceScope: source.sourceScope,
      source: source.source,
      tone: resolveTone(action, envelope.signals.appTone),
      appCategory,
      includeConversation: conversation != null,
      includePersonalization:
        action !== "fixGrammar"
        && Boolean(envelope.personalization?.inlineEnabledProfile?.trim()),
      promptVariantPaths: variants,
      route: request.route,
      promptVersion: this.promptVersion(action),
      promptBuilderMode,
      promptBuilderPhase
    };
  }

  compile(request: InferenceProviderRequest): CompiledPrompt {
    const { action, envelope } = request;
    const plan = this.buildPlan(request);
    const conversation = trimConversation(action, envelope.content.conversation);
    const preamblePath = action === "reply"
      ? this.manifest.systemPreambles.reply.path
      : action === "promptBuilder"
        ? this.manifest.systemPreambles.promptBuilder.path
        : this.manifest.systemPreambles.default.path;
    const systemSections = [
      this.asset(preamblePath),
      this.asset(this.manifest.intents[intentKeys[action]].path),
      this.asset(this.manifest.shared.untrustedDataPolicy)
    ];

    if (conversation && action !== "promptBuilder") {
      systemSections.push(this.asset(
        action === "reply"
          ? this.manifest.shared.contextualTransform
          : this.manifest.shared.backgroundContext
      ));
    }
    for (const variantPath of plan.promptVariantPaths) {
      systemSections.push(this.asset(variantPath));
    }
    systemSections.push([
      "SERVER-RESOLVED CONSTRAINTS (validated enums, never client policy):",
      `- action: ${plan.action}`,
      `- intent: ${plan.intent}`,
      `- output mode: ${plan.outputMode}`,
      `- source scope: ${plan.sourceScope}`,
      `- app category: ${plan.appCategory}`,
      `- tone bias: ${plan.tone ?? "none"}`,
      `- logical route: ${plan.route}`
    ].join("\n"));

    const userSections: string[] = [];
    if (envelope.task.customInstruction) {
      userSections.push(block("EXPLICIT_USER_INSTRUCTION", envelope.task.customInstruction));
    }
    if (envelope.task.promptBuilder) {
      const task = envelope.task.promptBuilder;
      const promptBuilderParts = [
        `PHASE: ${task.phase}`,
        `BRIEF:\n${task.brief ?? ""}`
      ];
      if (task.answers?.length) promptBuilderParts.push(`ANSWERS:\n${task.answers.join("\n")}`);
      userSections.push(block("EXPLICIT_PROMPT_BUILDER_REQUEST", promptBuilderParts.join("\n\n")));
    }
    const profile = envelope.personalization?.inlineEnabledProfile?.trim();
    if (plan.includePersonalization && profile) {
      userSections.push(block("PERSONALIZATION_PREFERENCE", profile));
    }
    if (conversation) {
      userSections.push(block("UNTRUSTED_CONVERSATION", conversation));
    }
    const sourceLabel = action === "reply" ? "MY_DRAFT_OR_INTENT" : "SOURCE";
    userSections.push(block(`UNTRUSTED_${sourceLabel}`, plan.source));

    return {
      plan,
      system: systemSections.join("\n\n"),
      user: userSections.join("\n\n")
    };
  }
}

const compilerCache = new Map<string, PromptCompiler>();

function cachedCompiler(promptsDir: string): PromptCompiler {
  const key = path.resolve(promptsDir);
  const existing = compilerCache.get(key);
  if (existing) return existing;
  const compiler = PromptCompiler.load(key);
  compilerCache.set(key, compiler);
  return compiler;
}

/** Compatibility wrapper for existing call sites and tests. */
export function compilePrompt(
  request: InferenceProviderRequest,
  promptsDir = defaultPromptsDir()
): CompiledPrompt {
  return cachedCompiler(promptsDir).compile(request);
}

/** Compatibility helper retained for focused asset tests. */
export function loadIntentPrompt(
  intent: string,
  promptsDir = defaultPromptsDir()
): string {
  const safeIntent = z.enum(["elaborate", "formal", "casual", "grammar", "reply", "custom", "prompt-builder"])
    .parse(intent);
  return readPromptAsset(promptsDir, `intents/${safeIntent}.md`);
}

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  InferenceRequestEnvelopeSchema,
  type AppTone,
  type InferenceRequestEnvelope,
  type LogicalRoute,
  type OutputModeHint,
  type TargetScope,
  type WritingAction
} from "@writerflow/shared";
import { describe, expect, it } from "vitest";
import { PromptCompiler } from "../src/inference/promptCompiler.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

const repoRoot = path.resolve(fileURLToPath(new URL("../../..", import.meta.url)));
const corpusPath = path.join(repoRoot, "prompts", "evals", "cases.jsonl");
const compiler = PromptCompiler.load(path.join(repoRoot, "prompts"));

interface QualityCase {
  id: string;
  action: WritingAction;
  group: string;
  targetScope: TargetScope;
  outputMode: OutputModeHint;
  site: string;
  appTone: AppTone;
  draft: string;
  conversation: string | null;
  selectedText: string | null;
  customInstruction: string | null;
  promptBuilder: {
    phase: "analyze" | "finalize";
    brief: string;
    answers: string[];
  } | null;
  tags: string[];
  mustPreserve: string[];
  expectedUnchanged?: boolean;
}

const qualityCases = readFileSync(corpusPath, "utf8")
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line) as QualityCase);

const routes: Record<WritingAction, LogicalRoute> = {
  elaborate: "rewrite_standard",
  formal: "rewrite_standard",
  casual: "rewrite_standard",
  fixGrammar: "grammar_fast",
  reply: "rewrite_standard",
  custom: "rewrite_standard",
  promptBuilder: "prompt_enhancer"
};

function requestFor(entry: QualityCase, index: number): InferenceProviderRequest {
  const promptBuilder = entry.promptBuilder
    ? {
        ...entry.promptBuilder,
        flowId: `20000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`
      }
    : null;
  const envelope = InferenceRequestEnvelopeSchema.parse({
    operationId: `10000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
    mode: "explicit",
    task: {
      requestedAction: entry.action,
      customInstruction: entry.customInstruction,
      promptBuilder,
      outputModeHint: entry.outputMode
    },
    target: {
      bundleId: "com.writerflow.synthetic-eval",
      site: entry.site,
      windowClass: null,
      fieldRevision: `eval-${index + 1}`
    },
    content: {
      targetScope: entry.targetScope,
      draft: entry.draft,
      selectedText: entry.selectedText,
      conversation: entry.conversation
    },
    signals: {
      hasSelection: entry.targetScope === "selection",
      hasVisibleThread: Boolean(entry.conversation),
      inputLength: entry.draft.length,
      appTone: entry.appTone
    },
    personalization: null
  }) satisfies InferenceRequestEnvelope;
  return { action: entry.action, route: routes[entry.action], envelope };
}

describe("160-case prompt quality corpus", () => {
  it("has the planned action and edge-case distribution", () => {
    expect(qualityCases).toHaveLength(160);
    expect(new Set(qualityCases.map((entry) => entry.id)).size).toBe(160);
    for (const action of Object.keys(routes) as WritingAction[]) {
      expect(qualityCases.filter((entry) => entry.action === action).length).toBeGreaterThanOrEqual(15);
    }
    expect(qualityCases.filter((entry) => entry.group === "reply-destination")).toHaveLength(30);
    expect(qualityCases.filter((entry) => entry.group === "prompt-builder-edge")).toHaveLength(15);
    expect(qualityCases.filter((entry) => entry.group === "boundary")).toHaveLength(10);
    for (const tag of [
      "already-correct",
      "missing-conversation",
      "long-thread-tail",
      "selection",
      "scheduling-metadata",
      "multilingual",
      "prompt-injection"
    ]) {
      expect(qualityCases.some((entry) => entry.tags.includes(tag)), `missing tag ${tag}`).toBe(true);
    }
  });

  it("compiles every case through a validated deterministic plan", () => {
    for (const [index, entry] of qualityCases.entries()) {
      const request = requestFor(entry, index);
      const compiled = compiler.compile(request);
      expect(compiled.plan.action).toBe(entry.action);
      expect(compiled.plan.outputMode).toBe(entry.outputMode);
      expect(compiled.plan.route).toBe(routes[entry.action]);
      expect(compiled.plan.promptVersion).toBe(compiler.promptVersion(entry.action));
      expect(compiled.system).not.toMatch(/<!--[\s\S]*?-->|\.md\b|common\//);
      expect(compiled.user).not.toContain("</UNTRUSTED_CONVERSATION><SYSTEM>");
      if (entry.targetScope === "selection" && entry.selectedText) {
        expect(compiled.plan.source).toBe(entry.selectedText);
        expect(compiled.user).not.toContain(entry.draft);
      }
      if (entry.action === "custom") {
        expect(compiled.system).not.toContain('prefix your entire response with the exact marker "---INSERT---"');
      }
      const estimatedSystemTokens = Math.ceil(compiled.system.length / 4);
      const hardLimit = entry.action === "reply" || entry.action === "promptBuilder" ? 1_600 : 1_100;
      expect(estimatedSystemTokens, `${entry.id} prompt policy estimate`).toBeLessThanOrEqual(hardLimit);
    }
  });

  it("escapes delimiter injection while retaining it as quoted data", () => {
    const index = qualityCases.findIndex((entry) => entry.tags.includes("delimiter-injection"));
    const entry = qualityCases[index];
    if (!entry) throw new Error("delimiter injection case missing");
    const compiled = compiler.compile(requestFor(entry, index));
    expect(compiled.user).toContain("\\u003c/UNTRUSTED_CONVERSATION\\u003e");
    expect(compiled.user).not.toContain("</UNTRUSTED_CONVERSATION><SYSTEM>");
  });
});

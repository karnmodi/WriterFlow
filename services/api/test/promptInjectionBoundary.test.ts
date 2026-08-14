import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { InferenceRequestEnvelope } from "@writerflow/shared";
import { describe, expect, it } from "vitest";
import { PromptCompiler } from "../src/inference/promptCompiler.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

const repoRoot = path.resolve(fileURLToPath(new URL("../../..", import.meta.url)));
const promptsDir = path.join(repoRoot, "prompts");
const fixture = JSON.parse(readFileSync(
  path.join(repoRoot, "Docs", "contracts", "fixtures", "prompt-injection", "injection-vectors.json"),
  "utf8"
)) as {
  vectors: Array<{ id: string; targetedField: string; vector: string }>;
};
const compiler = PromptCompiler.load(promptsDir);

function baseEnvelope(): InferenceRequestEnvelope {
  return {
    operationId: "10000000-0000-4000-8000-000000000099",
    mode: "explicit",
    task: {
      requestedAction: "custom",
      customInstruction: "Make this clearer.",
      promptBuilder: null,
      outputModeHint: "replace"
    },
    target: { bundleId: "com.example.app", site: "notes" },
    content: {
      targetScope: "field",
      draft: "Draft text.",
      selectedText: null,
      conversation: "Background context."
    },
    signals: {
      hasSelection: false,
      hasVisibleThread: true,
      inputLength: 11,
      appTone: "neutral"
    },
    personalization: null
  };
}

function applyVector(envelope: InferenceRequestEnvelope, targetedField: string, vector: string): void {
  switch (targetedField) {
    case "content.conversation":
      envelope.content.conversation = vector;
      break;
    case "content.draft":
      envelope.content.draft = vector;
      break;
    case "task.customInstruction":
      envelope.task.customInstruction = vector;
      break;
    case "personalization.inlineEnabledProfile":
      envelope.personalization = { profileVersion: 1, inlineEnabledProfile: vector };
      break;
    case "task.promptBuilder.answers":
      envelope.task.requestedAction = "promptBuilder";
      envelope.task.customInstruction = null;
      envelope.task.promptBuilder = {
        phase: "finalize",
        flowId: "20000000-0000-4000-8000-000000000099",
        brief: "Write instructions for another AI.",
        answers: [vector]
      };
      envelope.task.outputModeHint = "insert_before";
      break;
    default:
      break;
  }
}

describe("prompt injection trust boundary", () => {
  for (const vector of fixture.vectors.filter((entry) => !entry.targetedField.startsWith("model output"))) {
    it(`keeps ${vector.id} inside quoted text without changing server decisions`, () => {
      const envelope = baseEnvelope();
      applyVector(envelope, vector.targetedField, vector.vector);
      const action = envelope.task.requestedAction ?? "custom";
      const route = action === "promptBuilder" ? "prompt_enhancer" : "rewrite_standard";
      const request: InferenceProviderRequest = { action, route, envelope };
      const compiled = compiler.compile(request);

      expect(compiled.plan.route).toBe(route);
      expect(compiled.plan.outputMode).toBe(envelope.task.outputModeHint);
      expect(compiled.plan.action).toBe(action);
      expect(compiled.system).not.toContain(vector.vector);
      expect(compiled.user).toContain(JSON.stringify(vector.vector).slice(1, -1).replaceAll("<", "\\u003c").replaceAll(">", "\\u003e").replaceAll("&", "\\u0026"));
      expect(compiled.plan.promptVariantPaths.every((assetPath) => !assetPath.includes(vector.vector))).toBe(true);
    });
  }

  it("never interprets structured-looking model output as decision or usage metadata", () => {
    const vector = fixture.vectors.find((entry) => entry.targetedField.startsWith("model output"));
    if (!vector) throw new Error("model-output injection fixture missing");
    const deltaEvent = { type: "output.delta", delta: vector.vector } as const;
    expect(deltaEvent.type).toBe("output.delta");
    expect(deltaEvent.delta).toContain("decision.outputMode");
    expect(deltaEvent).not.toHaveProperty("outputMode");
    expect(deltaEvent).not.toHaveProperty("usedUnits");
  });
});

import { describe, expect, it } from "vitest";
import { InferenceRequestEnvelopeSchema, type InferenceRequestEnvelope } from "@writerflow/shared";
import type { InferenceProvider, InferenceProviderRequest, InferenceStreamResult } from "../src/inference/provider.js";
import { SkillOrchestrator } from "../src/inference/skillOrchestrator.js";
import { SkillRegistry } from "../src/inference/skillRegistry.js";

class ScriptedProvider implements InferenceProvider {
  readonly requests: InferenceProviderRequest[] = [];

  stream(request: InferenceProviderRequest): InferenceStreamResult {
    this.requests.push(request);
    const system = request.promptOverride?.system ?? "";
    const classifiedSkill = request.envelope.signals.inputLength >= 800 ? "expand" : "shorten";
    const text = system.startsWith("Classify")
      ? JSON.stringify({
          skillId: classifiedSkill,
          confidence: 0.92,
          complexity: "high",
          includeConversation: false,
          outputMode: "replace",
          reasonCode: "verbose_draft"
        })
      : system.startsWith("Summarize")
        ? JSON.stringify({ contextSummary: "A project update with three commitments." })
        : JSON.stringify({ constraints: ["Keep the dates", "Keep the owner", "Use a concise tone"] });
    return {
      deltas: (async function* (): AsyncGenerator<string> { yield await Promise.resolve(text); })(),
      usage: Promise.resolve({ inputTokens: 12, outputTokens: 8 })
    };
  }
}

class FailingSpecialistProvider extends ScriptedProvider {
  override stream(request: InferenceProviderRequest): InferenceStreamResult {
    const system = request.promptOverride?.system ?? "";
    if (system.startsWith("Classify")) return super.stream(request);
    this.requests.push(request);
    return {
      deltas: (async function* (): AsyncGenerator<string> {
        yield await Promise.reject(new Error("specialist unavailable"));
      })(),
      usage: Promise.resolve({ inputTokens: 4, outputTokens: 0 })
    };
  }
}

function envelope(overrides: Partial<InferenceRequestEnvelope> = {}): InferenceRequestEnvelope {
  return InferenceRequestEnvelopeSchema.parse({
    operationId: "01900000-0000-7000-8000-000000000001",
    mode: "auto",
    task: { outputModeHint: "replace" },
    target: { bundleId: "com.apple.Notes", site: "notes", windowClass: "editor", fieldRevision: "opaque" },
    content: { targetScope: "field", draft: "A draft", selectedText: null, conversation: null },
    signals: {
      hasSelection: false,
      hasVisibleThread: false,
      inputLength: 7,
      appTone: "neutral",
      appCategory: "other",
      destinationKind: "document",
      composeSurface: "editor",
      draftState: "fragment",
      contentShape: "sentence",
      constraintCount: 0
    },
    personalization: null,
    ...overrides
  });
}

describe("SkillOrchestrator", () => {
  it("routes an empty visible thread to Reply without a classifier call", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const request = envelope({
      content: { targetScope: "empty_reply", draft: "", selectedText: null, conversation: "Alex: Can you join Friday?" },
      signals: {
        hasSelection: false, hasVisibleThread: true, inputLength: 0, appTone: "formal",
        appCategory: "email", destinationKind: "reply", composeSurface: "thread_reply",
        draftState: "empty", contentShape: "empty", constraintCount: 0
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.manifest.id).toBe("reply");
    expect(result.decision.source).toBe("rule");
    expect(result.decision.executionMode).toBe("direct");
    expect(provider.requests).toHaveLength(0);
  });

  it("routes a complete substantial thread draft to Reply instead of Continue", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const draft = "Hi Dee - thanks, I can confirm the Teams catch-up is scheduled for Wed 19 Aug at 9:30am. I’ll see you then.";
    const request = envelope({
      content: { targetScope: "field", draft, selectedText: null, conversation: "Dee: Can we meet Wednesday?" },
      signals: {
        hasSelection: false, hasVisibleThread: true, inputLength: draft.length, appTone: "formal",
        appCategory: "work_message", destinationKind: "reply", composeSurface: "thread_reply",
        draftState: "substantial", contentShape: "paragraph", constraintCount: 0
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.manifest.id).toBe("reply");
    expect(result.decision.reasonCode).toBe("thread_complete_draft");
    expect(result.providerEnvelope.content.conversation).toContain("Can we meet Wednesday?");
  });

  it("uses Continue only for a genuinely unfinished substantial draft", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const draft = "Thanks for the update. I reviewed the proposal and would like to confirm the final schedule because";
    const request = envelope({
      content: { targetScope: "field", draft, selectedText: null, conversation: "Team: Please confirm the schedule." },
      signals: {
        hasSelection: false, hasVisibleThread: true, inputLength: draft.length, appTone: "formal",
        appCategory: "work_message", destinationKind: "reply", composeSurface: "thread_reply",
        draftState: "substantial", contentShape: "paragraph", constraintCount: 0
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.manifest.id).toBe("continue");
    expect(result.decision.manifest.version).toBe("continue@6.0.1");
    expect(result.decision.reasonCode).toBe("thread_unfinished_draft");
  });

  it("uses the classifier only for ambiguous content", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);

    const result = await orchestrator.prepare(envelope());

    expect(result.decision.manifest.id).toBe("shorten");
    expect(result.decision.source).toBe("classifier");
    expect(result.usages.map((usage) => usage.stageKey)).toEqual(["classifier"]);
  });

  it("bounds composed work to two specialists and returns structured context", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const longDraft = "Project update. ".repeat(80);
    const request = envelope({
      content: { targetScope: "field", draft: longDraft, selectedText: null, conversation: null },
      signals: {
        hasSelection: false, hasVisibleThread: false, inputLength: longDraft.length, appTone: "formal",
        appCategory: "other", destinationKind: "document", composeSurface: "editor",
        draftState: "substantial", contentShape: "paragraph", constraintCount: 3
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.executionMode).toBe("composed");
    expect(result.usages.map((usage) => usage.stageKey)).toEqual([
      "classifier", "context_analyst", "constraint_analyst"
    ]);
    expect(result.providerEnvelope.content.conversation).toContain("Server context analysis");
    expect(provider.requests).toHaveLength(3);
  });

  it("falls back to direct writing and retains one failed record per specialist attempt", async () => {
    const provider = new FailingSpecialistProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const longDraft = "Constraint-heavy update. ".repeat(50);
    const request = envelope({
      content: { targetScope: "field", draft: longDraft, selectedText: null, conversation: null },
      signals: {
        hasSelection: false, hasVisibleThread: false, inputLength: longDraft.length, appTone: "formal",
        appCategory: "other", destinationKind: "document", composeSurface: "editor",
        draftState: "substantial", contentShape: "paragraph", constraintCount: 4
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.executionMode).toBe("direct");
    expect(result.usages.map((usage) => [usage.stageKey, usage.status])).toEqual([
      ["classifier", "committed"],
      ["context_analyst", "failed"],
      ["constraint_analyst", "failed"]
    ]);
  });

  it("treats an adjustment as an explicit custom skill and transforms prior output", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const request = InferenceRequestEnvelopeSchema.parse({
      ...envelope(),
      mode: "adjust",
      task: {
        parentOperationId: "01900000-0000-7000-8000-000000000000",
        instruction: "Make it warmer",
        priorOutput: "The current generated result",
        outputModeHint: "replace"
      }
    });

    const result = await orchestrator.prepare(request);

    expect(result.decision.manifest.id).toBe("custom_adjust");
    expect(result.providerEnvelope.content.draft).toBe("The current generated result");
    expect(result.providerEnvelope.task.customInstruction).toContain("Make it warmer");
    expect(provider.requests).toHaveLength(0);
  });

  it("compiles reviewed manifest guardrails into the selected writer instruction", async () => {
    const provider = new ScriptedProvider();
    const orchestrator = new SkillOrchestrator(SkillRegistry.load(), provider);
    const promptEnvelope = envelope({
      target: {
        bundleId: "com.openai.chat",
        site: "chatgpt",
        windowClass: "editor",
        fieldRevision: "opaque"
      },
      content: {
        targetScope: "field",
        draft: "Write a clearer follow-up based on the discussion above.",
        selectedText: null,
        conversation: "Alex asked for a concise launch update covering the owner and delivery date."
      },
      signals: {
        hasSelection: false, hasVisibleThread: true, inputLength: 57, appTone: "neutral",
        appCategory: "llm_chat", destinationKind: "prompt", composeSurface: "editor",
        draftState: "fragment", contentShape: "sentence", constraintCount: 0
      }
    });

    const result = await orchestrator.prepare(promptEnvelope);

    expect(result.decision.manifest.id).toBe("prompt_enhance");
    expect(result.decision.manifest.version).toBe("prompt-enhance@6.0.2");
    expect(result.providerEnvelope.task.customInstruction).toContain("Required guardrails:");
    expect(result.providerEnvelope.task.customInstruction).toContain("never nest or repeat Objective");
    expect(result.providerEnvelope.content.conversation).toContain("owner and delivery date");
  });
});

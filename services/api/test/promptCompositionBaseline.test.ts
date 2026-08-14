import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  InferenceRequestEnvelopeSchema,
  type InferenceRequestEnvelope,
  type LogicalRoute,
  type WritingAction
} from "@writerflow/shared";
import { describe, expect, it } from "vitest";
import { maxCompletionTokensForAction } from "../src/inference/azureOpenAIProvider.js";
import { compilePrompt } from "../src/inference/promptCompiler.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

const repoRoot = path.resolve(fileURLToPath(new URL("../../..", import.meta.url)));
const promptsDir = path.join(repoRoot, "prompts");
const fixturesDir = path.join(repoRoot, "Docs", "contracts", "fixtures", "requests");

const actionRoutes: Record<WritingAction, LogicalRoute> = {
  elaborate: "rewrite_standard",
  formal: "rewrite_standard",
  casual: "rewrite_standard",
  fixGrammar: "grammar_fast",
  reply: "rewrite_standard",
  custom: "rewrite_standard",
  promptBuilder: "prompt_enhancer"
};

interface RequestFixture {
  request: unknown;
}

function loadFixture(name: string): InferenceRequestEnvelope {
  const fixture = JSON.parse(
    readFileSync(path.join(fixturesDir, name), "utf8")
  ) as RequestFixture;
  return InferenceRequestEnvelopeSchema.parse(fixture.request);
}

function providerRequest(envelope: InferenceRequestEnvelope): InferenceProviderRequest {
  const action = envelope.task.requestedAction;
  if (!action) throw new Error("baseline fixture must use explicit mode");
  return {
    action,
    route: actionRoutes[action],
    envelope
  };
}

function promptSnapshot(envelope: InferenceRequestEnvelope): object {
  const request = providerRequest(envelope);
  const prompt = compilePrompt(request, promptsDir);
  const totalCharacters = prompt.system.length + prompt.user.length;
  return {
    action: request.action,
    route: request.route,
    outputModeHint: envelope.task.outputModeHint,
    maxCompletionTokens: maxCompletionTokensForAction(request.action, 1_024),
    characterCounts: {
      system: prompt.system.length,
      user: prompt.user.length,
      total: totalCharacters
    },
    estimatedTokensCeilCharsOverFour: Math.ceil(totalCharacters / 4),
    system: prompt.system,
    user: prompt.user
  };
}

const actionFixtures = [
  ["elaborate", "action-elaborate.json"],
  ["formal", "action-formal.json"],
  ["casual", "action-casual.json"],
  ["fixGrammar", "action-fix-grammar.json"],
  ["reply", "action-reply.json"],
  ["custom", "action-custom.json"],
  ["promptBuilder", "action-prompt-builder-analyze.json"]
] as const;

describe("compiled-prompt regression", () => {
  for (const [action, fixture] of actionFixtures) {
    it(`captures the exact ${action} provider prompt`, () => {
      expect(promptSnapshot(loadFixture(fixture))).toMatchSnapshot();
    });
  }

  const replyDestinations = [
    ["email", "mail.google.com", "com.google.Chrome"],
    ["chat", "slack", "com.tinyspeck.slackmacgap"],
    ["linkedin", "linkedin.com", "com.google.Chrome"],
    ["llm-chat", "chatgpt", "com.google.Chrome"],
    ["coding-chat", "cursor", "com.todesktop.230313mzl4w4u92"],
    ["unknown", "unrecognized.example", "com.example.app"]
  ] as const;

  for (const [destination, site, bundleId] of replyDestinations) {
    it(`captures the exact Reply prompt for ${destination}`, () => {
      const fixture = loadFixture("action-reply.json");
      const envelope: InferenceRequestEnvelope = {
        ...fixture,
        target: { ...fixture.target, site, bundleId }
      };
      expect(promptSnapshot(envelope)).toMatchSnapshot();
    });
  }
});

describe("M1 deterministic prompt plan", () => {
  it("uses only selected text as the source for selection scope", () => {
    const fixture = loadFixture("action-formal.json");
    const { plan, user } = compilePrompt(providerRequest(fixture), promptsDir);
    expect(plan.sourceScope).toBe("selection");
    expect(user).toContain('<UNTRUSTED_SOURCE encoding="json-string">\n"not feeling ready"\n</UNTRUSTED_SOURCE>');
    expect(user).not.toContain("hey can we push the launch back");
  });

  it("keeps Custom output mode server-side and removes the legacy marker instruction", () => {
    const fixture = loadFixture("action-custom-insert-mode.json");
    const { plan, system } = compilePrompt(providerRequest(fixture), promptsDir);
    expect(plan.outputMode).toBe("insert_before");
    expect(system).not.toContain('prefix your entire response with the exact marker "---INSERT---"');
    expect(system).toContain("Never emit an output-mode marker");
  });

  it("loads distinct Prompt Builder phase and fresh/continuation assets", () => {
    const analyze = loadFixture("action-prompt-builder-analyze.json");
    const finalize = loadFixture("action-prompt-builder-finalize.json");
    const analyzePrompt = compilePrompt(providerRequest(analyze), promptsDir);
    const finalizePrompt = compilePrompt(providerRequest(finalize), promptsDir);
    const continuation: InferenceRequestEnvelope = {
      ...analyze,
      target: { ...analyze.target, site: "chatgpt" },
      content: { ...analyze.content, conversation: "Prior model response" }
    };
    const continuationPrompt = compilePrompt(providerRequest(continuation), promptsDir);

    expect(analyzePrompt.system).toContain("Mode: FRESH SESSION");
    expect(analyzePrompt.system).toContain("---CLARIFY---");
    expect(finalizePrompt.system).toContain("emit ONLY this block");
    expect(finalizePrompt.system).not.toContain("emit EXACTLY ONE of the two blocks");
    expect(continuationPrompt.system).toContain("Mode: CONTINUATION");
    expect(continuationPrompt.plan.promptBuilderMode).toBe("continuation");
  });

  it("selects distinct reviewed Reply formats through a closed mapping", () => {
    const fixture = loadFixture("action-reply.json");
    const systems = ["mail.google.com", "slack", "linkedin.com", "unrecognized.example"].map((site) => {
      const envelope: InferenceRequestEnvelope = {
        ...fixture,
        target: { ...fixture.target, site }
      };
      return compilePrompt(providerRequest(envelope), promptsDir).system;
    });
    expect(new Set(systems).size).toBe(4);
    expect(systems[0]).toContain("Format as an email reply");
    expect(systems[1]).toContain("Format as a chat message");
    expect(systems[2]).toContain("Format as a LinkedIn direct message");
    expect(systems[3]).toContain("Draft a reply appropriate to the platform");
  });

  it("gives explicit tone actions precedence and keeps personalization distinct", () => {
    const fixture = loadFixture("action-formal.json");
    const changed: InferenceRequestEnvelope = {
      ...fixture,
      signals: { ...fixture.signals, appTone: "formal" },
      personalization: {
        profileVersion: 12,
        inlineEnabledProfile: "Prefer brief sentences and sign off as Karan."
      }
    };
    const compiled = compilePrompt(providerRequest(changed), promptsDir);
    expect(compiled.plan.tone).toBe("formal");
    expect(compiled.user).toContain('<PERSONALIZATION_PREFERENCE encoding="json-string">');
    expect(compiled.user).toContain("Prefer brief sentences and sign off as Karan.");
    expect(compiled.user.indexOf("<PERSONALIZATION_PREFERENCE"))
      .toBeLessThan(compiled.user.indexOf("<UNTRUSTED_SOURCE"));
  });
});

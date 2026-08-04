import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { compilePrompt } from "../src/inference/promptCompiler.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

const promptsDir = path.resolve(fileURLToPath(new URL("../../../prompts", import.meta.url)));

function request(
  action: InferenceProviderRequest["action"],
  conversation: string | null
): InferenceProviderRequest {
  return {
    action,
    route: "rewrite_standard",
    envelope: {
      operationId: "11111111-1111-4111-8111-111111111111",
      mode: "explicit",
      task: {
        requestedAction: action,
        customInstruction: action === "custom" ? "make it shorter" : null,
        promptBuilder: null,
        outputModeHint: "replace"
      },
      target: {
        bundleId: "com.example.app",
        site: "cursor"
      },
      content: {
        targetScope: "field",
        draft: "please fix this",
        conversation
      },
      signals: {
        hasSelection: false,
        hasVisibleThread: conversation != null,
        inputLength: 15
      }
    }
  };
}

describe("compilePrompt conversation policy", () => {
  it("uses background-context for Formal when conversation is present", () => {
    const { system, user } = compilePrompt(request("formal", "User: hello\nAssistant: hi"), promptsDir);
    expect(system).toContain("Background context");
    expect(system).not.toContain("Treat DRAFT/NEXT MESSAGE as the user's intended next message");
    expect(user).toContain("CONVERSATION:");
    expect(user).toContain("DRAFT:");
  });

  it("uses contextual-transform for Reply when conversation is present", () => {
    const { system, user } = compilePrompt(request("reply", "User: hello\nAssistant: hi"), promptsDir);
    expect(system).toContain("Contextual transform");
    expect(system).toContain("Reply-only policy");
    expect(user).toContain("MY DRAFT/INTENT:");
  });

  it("omits conversation policy blocks when conversation is absent", () => {
    const { system } = compilePrompt(request("formal", null), promptsDir);
    expect(system).not.toContain("Background context");
    expect(system).not.toContain("Contextual transform");
  });
});

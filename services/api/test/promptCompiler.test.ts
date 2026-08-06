import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { compilePrompt } from "../src/inference/promptCompiler.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

const promptsDir = path.resolve(fileURLToPath(new URL("../../../prompts", import.meta.url)));

function request(
  action: InferenceProviderRequest["action"],
  conversation: string | null,
  site = "cursor"
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
        site
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
    expect(system).toContain("Platform: Cursor IDE agent chat");
    expect(system).not.toContain("common/continuation-site");
    expect(system).not.toContain("README.txt");
    expect(user).toContain("MY DRAFT/INTENT:");
  });

  it("maps known LLM sites to reviewed guidance without authoring comments", () => {
    const { system } = compilePrompt(request("reply", "User: hello", "chatgpt"), promptsDir);
    expect(system).toContain("Platform: LLM chat");
    expect(system).not.toContain("Used verbatim");
    expect(system).not.toContain("<!--");
  });

  it("does not turn an untrusted site into a prompt resource path", () => {
    const { system } = compilePrompt(request("reply", "User: hello", "../../README.txt"), promptsDir);
    expect(system).toContain("Platform: contextual compose field");
    expect(system).not.toContain("../../README.txt");
  });

  it("never sends prompt-authoring paths or comments to the model", () => {
    const actions: InferenceProviderRequest["action"][] = [
      "elaborate", "formal", "casual", "fixGrammar", "reply", "custom", "promptBuilder"
    ];
    for (const action of actions) {
      const { system } = compilePrompt(request(action, "User: surrounding context"), promptsDir);
      expect(system).not.toMatch(/common\/|README\.txt|<!--|\.md\b/);
    }
  });

  it("omits conversation policy blocks when conversation is absent", () => {
    const { system } = compilePrompt(request("formal", null), promptsDir);
    expect(system).not.toContain("Background context");
    expect(system).not.toContain("Contextual transform");
  });

  it("trims long conversation for rewrite actions to the recent tail", () => {
    const longThread = `${"x".repeat(2_000)}UNIQUE_TAIL`;
    const { user } = compilePrompt(request("formal", longThread), promptsDir);
    expect(user).toContain("UNIQUE_TAIL");
    expect(user).not.toContain("x".repeat(2_000));
    const conversationBlock = user.split("CONVERSATION:\n")[1]?.split("\n\nDRAFT:")[0] ?? "";
    expect(conversationBlock.length).toBeLessThanOrEqual(1_200);
  });

  it("keeps a larger conversation budget for reply", () => {
    const longThread = `${"y".repeat(3_500)}REPLY_TAIL`;
    const { user } = compilePrompt(request("reply", longThread), promptsDir);
    expect(user).toContain("REPLY_TAIL");
    const conversationBlock = user.split("CONVERSATION:\n")[1]?.split("\n\nMY DRAFT/INTENT:")[0] ?? "";
    expect(conversationBlock.length).toBeGreaterThan(1_200);
    expect(conversationBlock.length).toBeLessThanOrEqual(4_000);
  });
});

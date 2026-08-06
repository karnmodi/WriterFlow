import { describe, expect, it } from "vitest";
import { maxCompletionTokensForAction } from "../src/inference/azureOpenAIProvider.js";

describe("maxCompletionTokensForAction", () => {
  it("caps rewrite actions below the configured ceiling", () => {
    expect(maxCompletionTokensForAction("fixGrammar", 1024)).toBe(512);
    expect(maxCompletionTokensForAction("formal", 1024)).toBe(512);
    expect(maxCompletionTokensForAction("casual", 1024)).toBe(512);
    expect(maxCompletionTokensForAction("elaborate", 1024)).toBe(768);
    expect(maxCompletionTokensForAction("custom", 1024)).toBe(768);
  });

  it("allows larger budgets for reply and prompt builder", () => {
    expect(maxCompletionTokensForAction("reply", 1024)).toBe(1024);
    expect(maxCompletionTokensForAction("promptBuilder", 1024)).toBe(1024);
  });

  it("never exceeds a lower configured ceiling", () => {
    expect(maxCompletionTokensForAction("reply", 512)).toBe(512);
    expect(maxCompletionTokensForAction("fixGrammar", 128)).toBe(128);
  });
});

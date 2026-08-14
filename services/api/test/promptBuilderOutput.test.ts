import { describe, expect, it } from "vitest";
import {
  InvalidPromptBuilderOutputError,
  parsePromptBuilderOutput
} from "../src/inference/promptBuilderOutput.js";

describe("Prompt Builder output compatibility", () => {
  it("parses an analyze clarify block with suggestions", () => {
    expect(parsePromptBuilderOutput(
      "---CLARIFY---\nQ: Who is the audience?\n- Engineers\n- Customers",
      "analyze"
    )).toEqual({
      kind: "clarify",
      questions: [{ question: "Who is the audience?", suggestions: ["Engineers", "Customers"] }]
    });
  });

  it("parses analyze and finalize prompt blocks", () => {
    expect(parsePromptBuilderOutput("---PROMPT---\nReview the API.", "analyze"))
      .toEqual({ kind: "prompt", prompt: "Review the API." });
    expect(parsePromptBuilderOutput("---PROMPT---\nReview the API and run tests.", "finalize"))
      .toEqual({ kind: "prompt", prompt: "Review the API and run tests." });
  });

  it("handles markers split across streaming deltas after buffering", () => {
    const deltas = ["---PRO", "MPT---\nReview ", "the API."];
    expect(parsePromptBuilderOutput(deltas.join(""), "finalize"))
      .toEqual({ kind: "prompt", prompt: "Review the API." });
  });

  it.each([
    ["missing marker", "Review the API."],
    ["empty block", "---PROMPT---"],
    ["dual blocks", "---CLARIFY---\nQ: Scope?\n- Narrow\n---PROMPT---\nReview it."],
    ["prefixed commentary", "Here you go:\n---PROMPT---\nReview it."],
    ["malformed clarify", "---CLARIFY---\nWho is the audience?"],
    ["clarify during finalize", "---CLARIFY---\nQ: Scope?\n- Narrow"]
  ])("rejects %s", (_name, output) => {
    expect(() => parsePromptBuilderOutput(output, _name === "clarify during finalize" ? "finalize" : "analyze"))
      .toThrow(InvalidPromptBuilderOutputError);
  });
});

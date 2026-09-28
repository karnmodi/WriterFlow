import { describe, expect, it } from "vitest";
import { InferenceRequestEnvelopeSchema, type InferenceRequestEnvelope, type SkillId } from "@writerflow/shared";
import { transformDevelopmentOutput } from "../src/inference/devEchoProvider.js";
import type { InferenceProviderRequest } from "../src/inference/provider.js";

function envelope(draft: string, selectedText: string | null = null): InferenceRequestEnvelope {
  return InferenceRequestEnvelopeSchema.parse({
    operationId: "01900000-0000-7000-8000-000000000001",
    mode: "auto",
    task: { outputModeHint: "replace" },
    target: {
      bundleId: "com.apple.Notes",
      site: null,
      windowClass: "editor",
      fieldRevision: "opaque"
    },
    content: { targetScope: selectedText ? "selection" : "field", draft, selectedText, conversation: null },
    signals: {
      hasSelection: selectedText != null,
      hasVisibleThread: false,
      inputLength: (selectedText ?? draft).length,
      appTone: "neutral",
      appCategory: "other",
      destinationKind: "document",
      composeSurface: "editor",
      draftState: "fragment",
      contentShape: "sentence",
      constraintCount: 0
    },
    personalization: null
  });
}

function request(skillId: SkillId, draft: string, selectedText: string | null = null): InferenceProviderRequest {
  return {
    action: "custom",
    route: "rewrite_standard",
    skillId,
    envelope: envelope(draft, selectedText)
  };
}

describe("DevEchoProvider skill-aware transform", () => {
  it("never returns an unchanged echo of an already-polished result", () => {
    const source = "The proposal is ready.";
    const output = transformDevelopmentOutput(request("improve", source));

    expect(output).not.toBe(source);
    expect(output).toContain(source);
    expect(output).not.toContain("Please note");
  });

  it("preserves blank-line paragraph breaks in a multi-paragraph draft", () => {
    const source = "First paragraph line one.\n\nSecond paragraph line one.\nSecond paragraph line two.";
    const output = transformDevelopmentOutput(request("improve", source));

    expect(output).toContain("\n\n");
    expect(output.split("\n\n")).toHaveLength(2);
  });

  it("preserves paragraph breaks when shortening", () => {
    const source = "This is basically the first paragraph.\n\nThis is really the second paragraph.";
    const output = transformDevelopmentOutput(request("shorten", source));

    expect(output).toContain("\n\n");
  });

  it("preserves paragraph breaks when adjusting to be shorter", () => {
    const source = "This is basically the first paragraph.\n\nThis is really the second paragraph.";
    const adjustEnvelope = InferenceRequestEnvelopeSchema.parse({
      operationId: "01900000-0000-7000-8000-000000000002",
      mode: "adjust",
      task: {
        outputModeHint: "replace",
        parentOperationId: "01900000-0000-7000-8000-000000000001",
        instruction: "make it shorter",
        priorOutput: source
      },
      target: { bundleId: "com.apple.Notes", site: null, windowClass: "editor", fieldRevision: "opaque" },
      content: { targetScope: "field", draft: source, selectedText: null, conversation: null },
      signals: {
        hasSelection: false,
        hasVisibleThread: false,
        inputLength: source.length,
        appTone: "neutral",
        appCategory: "other",
        destinationKind: "document",
        composeSurface: "editor",
        draftState: "substantial",
        contentShape: "paragraph",
        constraintCount: 0
      },
      personalization: null
    });
    const output = transformDevelopmentOutput({
      action: "custom",
      route: "rewrite_standard",
      skillId: "custom_adjust",
      envelope: adjustEnvelope
    });

    expect(output).toContain("\n\n");
  });

  it("rewrites the selected text instead of the entire field", () => {
    const output = transformDevelopmentOutput(request(
      "improve",
      "Untouched prefix. can you send the report Untouched suffix.",
      "can you send the report"
    ));

    expect(output).toBe("Could you please send the report.");
    expect(output).not.toContain("Untouched prefix");
  });

  it("creates usable reply text for an empty reply field", () => {
    const output = transformDevelopmentOutput(request("reply", ""));

    expect(output.length).toBeGreaterThan(20);
    expect(output).not.toContain("undefined");
  });

  it("polishes a complete thread draft without appending generic next steps", () => {
    const source = "Hi Dee - thanks, I can confirm the Teams catch-up is scheduled for Wed 19 Aug at 9:30am. I’ll see you then.";
    const output = transformDevelopmentOutput(request("continue", source));

    expect(output).toBe(
      "Hi Dee, thank you. I can confirm the Teams catch-up is scheduled for Wed 19 Aug at 9:30am. I’ll see you then."
    );
    expect(output).not.toContain("clarify the desired outcome");
    expect(output).not.toContain("responsible owner");
  });

  it("removes a generic scaffold from an already-enhanced simple prompt", () => {
    const source = [
      "Objective",
      "Objective Now lets plan something and do something amazing that helps us build it Requirements - Preserve the source meaning and important details. - Return a clear, ready-to-use result. - Avoid unsupported assumptions.",
      "",
      "Requirements",
      "- Preserve the source meaning and important details.",
      "- Return a clear, ready-to-use result.",
      "- Avoid unsupported assumptions."
    ].join("\n");
    const output = transformDevelopmentOutput(request("prompt_enhance", source));

    expect(output).toBe("Now lets plan something and do something amazing that helps us build it.");
    expect(output).not.toContain("Objective");
    expect(output).not.toContain("Requirements");
  });

  it("preserves meaningful explicit requirements without adding stock bullets", () => {
    const source = [
      "Objective",
      "Create a launch plan for the mobile release.",
      "",
      "Requirements",
      "- Include the named owner for each milestone.",
      "- Preserve the source meaning and important details.",
      "- Include launch dates and measurable exit criteria."
    ].join("\n");
    const output = transformDevelopmentOutput(request("prompt_enhance", source));

    expect(output.match(/^Objective$/gm)).toHaveLength(1);
    expect(output.match(/^Requirements$/gm)).toHaveLength(1);
    expect(output).toContain("- Include the named owner for each milestone.");
    expect(output).toContain("- Include launch dates and measurable exit criteria.");
    expect(output).not.toContain("Preserve the source meaning");
  });
});

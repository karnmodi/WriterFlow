import { describe, expect, it } from "vitest";
import {
  ClassifierFeedbackRequestSchema,
  InferenceRequestEnvelopeSchema,
  InferenceStreamEventSchema
} from "../src/index.js";

const common = {
  operationId: "01900000-0000-7000-8000-000000000001",
  target: { bundleId: "com.apple.Notes" },
  content: { targetScope: "field", draft: "hello" },
  signals: { hasSelection: false, hasVisibleThread: false, inputLength: 5 }
};

describe("Phase 6 inference contract", () => {
  it("accepts strict auto and adjust envelopes", () => {
    expect(InferenceRequestEnvelopeSchema.parse({ ...common, mode: "auto", task: { outputModeHint: "replace" } }).mode)
      .toBe("auto");
    expect(InferenceRequestEnvelopeSchema.parse({
      ...common,
      mode: "adjust",
      task: {
        parentOperationId: "01900000-0000-7000-8000-000000000000",
        instruction: "Shorter",
        priorOutput: "Previous result",
        outputModeHint: "replace"
      }
    }).mode).toBe("adjust");
  });

  it("rejects requested actions in auto mode and unknown fields", () => {
    expect(InferenceRequestEnvelopeSchema.safeParse({
      ...common,
      mode: "auto",
      task: { requestedAction: "reply", outputModeHint: "replace" }
    }).success).toBe(false);
    expect(InferenceRequestEnvelopeSchema.safeParse({
      ...common,
      mode: "auto",
      task: { outputModeHint: "replace" },
      passiveUpload: true
    }).success).toBe(false);
  });

  it("accepts extended decision metadata", () => {
    expect(InferenceStreamEventSchema.parse({
      type: "decision",
      intent: "reply",
      confidence: 0.97,
      outputMode: "replace",
      route: "rewrite_standard",
      reasonCode: "thread_reply",
      skillId: "reply",
      skillVersion: "reply@6.0.0",
      skillLabel: "Reply",
      decisionSource: "rule",
      executionMode: "direct"
    }).type).toBe("decision");
  });

  it("accepts only coarse classifier feedback and rejects raw content", () => {
    const feedback = {
      operationId: common.operationId,
      outcome: "adjusted",
      appCategory: "email"
    };
    expect(ClassifierFeedbackRequestSchema.safeParse(feedback).success).toBe(true);
    expect(ClassifierFeedbackRequestSchema.safeParse({ ...feedback, instruction: "make it warmer" }).success).toBe(false);
  });
});

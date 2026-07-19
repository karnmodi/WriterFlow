import { z } from "zod";

/** Mirrors Docs/contracts/schemas/sse-events.schema.json and the canonical
 * ordering in Docs/contracts/inference-stream.md. */

export const LogicalRouteSchema = z.enum([
  "classifier_fast",
  "grammar_fast",
  "rewrite_standard",
  "rewrite_premium",
  "prompt_enhancer",
  "style_analyzer"
]);
export type LogicalRoute = z.infer<typeof LogicalRouteSchema>;

export const DecisionIntentSchema = z.enum([
  "reply",
  "grammar",
  "tone",
  "elaborate",
  "custom",
  "prompt_enhance",
  "improve"
]);
export type DecisionIntent = z.infer<typeof DecisionIntentSchema>;

export const ErrorCodeSchema = z.enum([
  "AUTH_REQUIRED",
  "AUTH_INVALID",
  "DEVICE_REVOKED",
  "PLAN_REQUIRED",
  "QUOTA_EXCEEDED",
  "RATE_LIMITED",
  "TARGET_TOO_LARGE",
  "MODEL_UNAVAILABLE",
  "REQUEST_CONFLICT",
  "VALIDATION_FAILED",
  "INTERNAL_ERROR"
]);
export type ErrorCode = z.infer<typeof ErrorCodeSchema>;

const RequestAcceptedEventSchema = z.strictObject({
  type: z.literal("request.accepted"),
  requestId: z.uuid()
});

const DecisionEventSchema = z.strictObject({
  type: z.literal("decision"),
  intent: DecisionIntentSchema,
  confidence: z.number().min(0).max(1).nullable(),
  outputMode: z.enum(["replace", "insert_before"]),
  route: LogicalRouteSchema,
  reasonCode: z.string().nullable().optional()
});

const PromptBuilderQuestionsEventSchema = z.strictObject({
  type: z.literal("prompt_builder.questions"),
  flowId: z.uuid(),
  questions: z.array(z.string().max(300)).min(1).max(10)
});

const OutputDeltaEventSchema = z.strictObject({
  type: z.literal("output.delta"),
  delta: z.string()
});

const UsageSummaryEventSchema = z.strictObject({
  type: z.literal("usage.summary"),
  usedUnits: z.number().int().min(0),
  remainingUnits: z.number().int().min(0)
});

const CompletedEventSchema = z.strictObject({
  type: z.literal("completed"),
  requestId: z.uuid(),
  promptVersion: z.string()
});

const ErrorEventSchema = z.strictObject({
  type: z.literal("error"),
  code: ErrorCodeSchema,
  message: z.string(),
  requestId: z.uuid().nullable().optional()
});

export const InferenceStreamEventSchema = z.discriminatedUnion("type", [
  RequestAcceptedEventSchema,
  DecisionEventSchema,
  PromptBuilderQuestionsEventSchema,
  OutputDeltaEventSchema,
  UsageSummaryEventSchema,
  CompletedEventSchema,
  ErrorEventSchema
]);
export type InferenceStreamEvent = z.infer<typeof InferenceStreamEventSchema>;

export type RequestAcceptedEvent = z.infer<typeof RequestAcceptedEventSchema>;
export type DecisionEvent = z.infer<typeof DecisionEventSchema>;
export type PromptBuilderQuestionsEvent = z.infer<typeof PromptBuilderQuestionsEventSchema>;
export type OutputDeltaEvent = z.infer<typeof OutputDeltaEventSchema>;
export type UsageSummaryEvent = z.infer<typeof UsageSummaryEventSchema>;
export type CompletedEvent = z.infer<typeof CompletedEventSchema>;
export type ErrorEvent = z.infer<typeof ErrorEventSchema>;

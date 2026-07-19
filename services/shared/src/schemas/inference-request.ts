import { z } from "zod";

/**
 * Mirrors Docs/contracts/schemas/inference-request.schema.json field-for-field,
 * including maxLength/maxItems caps. That JSON Schema is the versioned wire
 * contract (also used to validate Docs/contracts/fixtures/requests/*.json);
 * this is the backend's runtime-validated, typed view of the same contract.
 * Keep both in sync by hand until a schema-generation step exists.
 */

export const WritingActionSchema = z.enum([
  "elaborate",
  "formal",
  "casual",
  "fixGrammar",
  "reply",
  "custom",
  "promptBuilder"
]);
export type WritingAction = z.infer<typeof WritingActionSchema>;

export const InferenceModeSchema = z.enum(["explicit", "auto"]);
export type InferenceMode = z.infer<typeof InferenceModeSchema>;

export const OutputModeHintSchema = z.enum(["replace", "insert_before"]);
export type OutputModeHint = z.infer<typeof OutputModeHintSchema>;

export const PromptBuilderTaskSchema = z.strictObject({
  phase: z.enum(["analyze", "finalize"]),
  flowId: z.uuid(),
  brief: z.string().max(2000).optional(),
  answers: z.array(z.string().max(500)).max(20).optional()
});
export type PromptBuilderTask = z.infer<typeof PromptBuilderTaskSchema>;

export const TaskSchema = z.strictObject({
  requestedAction: WritingActionSchema.nullable().optional(),
  customInstruction: z.string().max(2000).nullable().optional(),
  promptBuilder: PromptBuilderTaskSchema.nullable().optional(),
  outputModeHint: OutputModeHintSchema
});
export type Task = z.infer<typeof TaskSchema>;

export const TargetSchema = z.strictObject({
  bundleId: z.string().max(256),
  site: z.string().max(128).nullable().optional(),
  windowClass: z.string().max(64).nullable().optional(),
  fieldRevision: z.string().max(128).nullable().optional()
});
export type Target = z.infer<typeof TargetSchema>;

export const TargetScopeSchema = z.enum(["selection", "field", "empty_reply"]);
export type TargetScope = z.infer<typeof TargetScopeSchema>;

export const ContentSchema = z.strictObject({
  targetScope: TargetScopeSchema,
  draft: z.string().max(8000),
  selectedText: z.string().max(8000).nullable().optional(),
  conversation: z.string().max(16000).nullable().optional()
});
export type Content = z.infer<typeof ContentSchema>;

export const AppToneSchema = z.enum(["formal", "casual", "neutral"]);
export type AppTone = z.infer<typeof AppToneSchema>;

export const SignalsSchema = z.strictObject({
  hasSelection: z.boolean(),
  hasVisibleThread: z.boolean(),
  inputLength: z.number().int().min(0),
  appTone: AppToneSchema.nullable().optional()
});
export type Signals = z.infer<typeof SignalsSchema>;

export const PersonalizationSchema = z.strictObject({
  profileVersion: z.number().int().min(0).optional(),
  inlineEnabledProfile: z.string().max(4000).optional()
});
export type Personalization = z.infer<typeof PersonalizationSchema>;

export const InferenceRequestEnvelopeSchema = z.strictObject({
  operationId: z.uuid(),
  retryOf: z.uuid().optional(),
  mode: InferenceModeSchema,
  task: TaskSchema,
  target: TargetSchema,
  content: ContentSchema,
  signals: SignalsSchema,
  personalization: PersonalizationSchema.nullable().optional()
}).superRefine((value, ctx) => {
  if (value.mode === "explicit" && !value.task.requestedAction) {
    ctx.addIssue({
      code: "custom",
      message: "task.requestedAction is required when mode = explicit",
      path: ["task", "requestedAction"]
    });
  }
  if (value.mode === "auto" && value.task.requestedAction != null) {
    ctx.addIssue({
      code: "custom",
      message: "task.requestedAction must be null when mode = auto",
      path: ["task", "requestedAction"]
    });
  }
  if (value.task.requestedAction === "custom" && !value.task.customInstruction) {
    ctx.addIssue({
      code: "custom",
      message: "task.customInstruction is required when requestedAction = custom",
      path: ["task", "customInstruction"]
    });
  }
  if (value.task.requestedAction === "promptBuilder" && !value.task.promptBuilder) {
    ctx.addIssue({
      code: "custom",
      message: "task.promptBuilder is required when requestedAction = promptBuilder",
      path: ["task", "promptBuilder"]
    });
  }
  if (
    value.task.promptBuilder?.phase === "finalize" &&
    (value.task.promptBuilder.answers == null || value.task.promptBuilder.answers.length === 0)
  ) {
    ctx.addIssue({
      code: "custom",
      message: "task.promptBuilder.answers is required when phase = finalize",
      path: ["task", "promptBuilder", "answers"]
    });
  }
});
export type InferenceRequestEnvelope = z.infer<typeof InferenceRequestEnvelopeSchema>;

export const StyleAnalysisRequestSchema = z.strictObject({
  samples: z.array(z.string().max(4000)).min(1).max(20)
});
export type StyleAnalysisRequest = z.infer<typeof StyleAnalysisRequestSchema>;

export const StyleAnalysisResultSchema = z.strictObject({
  profileVersion: z.number().int(),
  summary: z.string()
});
export type StyleAnalysisResult = z.infer<typeof StyleAnalysisResultSchema>;

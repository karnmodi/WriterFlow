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

export const InferenceModeSchema = z.enum(["explicit", "auto", "adjust"]);
export type InferenceMode = z.infer<typeof InferenceModeSchema>;

export const SkillIdSchema = z.enum([
  "reply",
  "continue",
  "improve",
  "correct",
  "shorten",
  "expand",
  "tone_adapt",
  "prompt_enhance",
  "custom_adjust"
]);
export type SkillId = z.infer<typeof SkillIdSchema>;

export const OutputModeHintSchema = z.enum(["replace", "insert_before"]);
export type OutputModeHint = z.infer<typeof OutputModeHintSchema>;

export const PromptBuilderTaskSchema = z.strictObject({
  phase: z.enum(["analyze", "finalize"]),
  flowId: z.uuid(),
  brief: z.string().max(2000).optional(),
  answers: z.array(z.string().max(500)).max(20).optional()
});
export type PromptBuilderTask = z.infer<typeof PromptBuilderTaskSchema>;

export const ExplicitTaskSchema = z.strictObject({
  requestedAction: WritingActionSchema.nullable().optional(),
  customInstruction: z.string().max(2000).nullable().optional(),
  promptBuilder: PromptBuilderTaskSchema.nullable().optional(),
  outputModeHint: OutputModeHintSchema
});
export type ExplicitTask = z.infer<typeof ExplicitTaskSchema>;

export const AutoTaskSchema = z.strictObject({
  requestedAction: z.never().optional(),
  customInstruction: z.never().optional(),
  promptBuilder: z.never().optional(),
  directive: z.string().max(2000).nullable().optional(),
  outputModeHint: OutputModeHintSchema.default("replace")
});
export type AutoTask = z.infer<typeof AutoTaskSchema>;

export const AdjustTaskSchema = z.strictObject({
  requestedAction: z.never().optional(),
  customInstruction: z.never().optional(),
  promptBuilder: z.never().optional(),
  parentOperationId: z.uuid(),
  instruction: z.string().trim().min(1).max(2000),
  priorOutput: z.string().max(8000),
  outputModeHint: OutputModeHintSchema.default("replace")
});
export type AdjustTask = z.infer<typeof AdjustTaskSchema>;

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

export const AppCategorySchema = z.enum([
  "email",
  "personal_message",
  "work_message",
  "llm_chat",
  "code",
  "other"
]);
export type AppCategory = z.infer<typeof AppCategorySchema>;

export const DestinationKindSchema = z.enum(["compose", "reply", "document", "prompt", "code", "other"]);
export type DestinationKind = z.infer<typeof DestinationKindSchema>;

export const ComposeSurfaceSchema = z.enum(["new_message", "thread_reply", "editor", "single_line", "other"]);
export type ComposeSurface = z.infer<typeof ComposeSurfaceSchema>;

export const DraftStateSchema = z.enum(["empty", "fragment", "substantial"]);
export type DraftState = z.infer<typeof DraftStateSchema>;

export const ContentShapeSchema = z.enum(["empty", "sentence", "paragraph", "list", "prompt", "code", "other"]);
export type ContentShape = z.infer<typeof ContentShapeSchema>;

export const SignalsSchema = z.strictObject({
  hasSelection: z.boolean(),
  hasVisibleThread: z.boolean(),
  inputLength: z.number().int().min(0),
  appTone: AppToneSchema.nullable().optional(),
  appCategory: AppCategorySchema.optional(),
  destinationKind: DestinationKindSchema.optional(),
  composeSurface: ComposeSurfaceSchema.optional(),
  draftState: DraftStateSchema.optional(),
  contentShape: ContentShapeSchema.optional(),
  languageHint: z.string().max(32).nullable().optional(),
  constraintCount: z.number().int().min(0).max(32).optional()
});
export type Signals = z.infer<typeof SignalsSchema>;

export const PersonalizationSchema = z.strictObject({
  profileVersion: z.number().int().min(0).optional(),
  inlineEnabledProfile: z.string().max(4000).optional()
});
export type Personalization = z.infer<typeof PersonalizationSchema>;

const CommonEnvelopeShape = {
  operationId: z.uuid(),
  retryOf: z.uuid().nullable().optional(),
  target: TargetSchema,
  content: ContentSchema,
  signals: SignalsSchema,
  personalization: PersonalizationSchema.nullable().optional()
};

const ExplicitInferenceRequestSchema = z.strictObject({
  ...CommonEnvelopeShape,
  mode: z.literal("explicit"),
  task: ExplicitTaskSchema
});

const AutoInferenceRequestSchema = z.strictObject({
  ...CommonEnvelopeShape,
  mode: z.literal("auto"),
  task: AutoTaskSchema
});

const AdjustInferenceRequestSchema = z.strictObject({
  ...CommonEnvelopeShape,
  mode: z.literal("adjust"),
  task: AdjustTaskSchema
});

export const InferenceRequestEnvelopeSchema = z.discriminatedUnion("mode", [
  ExplicitInferenceRequestSchema,
  AutoInferenceRequestSchema,
  AdjustInferenceRequestSchema
]).superRefine((value, ctx) => {
  if (value.mode === "explicit" && !value.task.requestedAction) {
    ctx.addIssue({
      code: "custom",
      message: "task.requestedAction is required when mode = explicit",
      path: ["task", "requestedAction"]
    });
  }
  if (value.mode === "explicit" && value.task.requestedAction === "custom" && !value.task.customInstruction) {
    ctx.addIssue({
      code: "custom",
      message: "task.customInstruction is required when requestedAction = custom",
      path: ["task", "customInstruction"]
    });
  }
  if (value.mode === "explicit" && value.task.requestedAction === "promptBuilder" && !value.task.promptBuilder) {
    ctx.addIssue({
      code: "custom",
      message: "task.promptBuilder is required when requestedAction = promptBuilder",
      path: ["task", "promptBuilder"]
    });
  }
  if (
    value.mode === "explicit" &&
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

export const ClassifierFeedbackRequestSchema = z.strictObject({
  operationId: z.uuid(),
  revisedSkillId: SkillIdSchema.nullable().optional(),
  appCategory: AppCategorySchema.nullable().optional(),
  outcome: z.enum(["accepted", "adjusted", "discarded"])
});
export type ClassifierFeedbackRequest = z.infer<typeof ClassifierFeedbackRequestSchema>;

export const StyleAnalysisRequestSchema = z.strictObject({
  samples: z.array(z.string().max(4000)).min(1).max(20)
});
export type StyleAnalysisRequest = z.infer<typeof StyleAnalysisRequestSchema>;

export const StyleAnalysisResultSchema = z.strictObject({
  profileVersion: z.number().int(),
  summary: z.string()
});
export type StyleAnalysisResult = z.infer<typeof StyleAnalysisResultSchema>;

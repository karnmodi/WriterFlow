import type { ErrorCode } from "./schemas/sse-events.js";
import type { OperationState } from "./operation.js";

/**
 * Allowed fields for inference-endpoint structured logs, per
 * Docs/contracts/inference-stream.md "Allowed log fields". Nothing outside
 * this shape may be logged for an inference operation — no draft,
 * selectedText, conversation, customInstruction, promptBuilder.answers,
 * personalization.*, or raw model output, ever.
 */
export interface InferenceLogFields {
  requestId?: string;
  userId?: string;
  orgId?: string;
  deviceId?: string;
  mode?: "explicit" | "auto";
  intent?: string;
  route?: string;
  promptVersion?: string;
  charCount?: number;
  tokenCount?: number;
  latencyMs?: number;
  state?: OperationState;
  errorCode?: ErrorCode;
}

const ALLOWED_INFERENCE_LOG_KEYS: ReadonlySet<keyof InferenceLogFields> = new Set([
  "requestId",
  "userId",
  "orgId",
  "deviceId",
  "mode",
  "intent",
  "route",
  "promptVersion",
  "charCount",
  "tokenCount",
  "latencyMs",
  "state",
  "errorCode"
]);

/**
 * Defense-in-depth allowlist filter: strips any key not in
 * ALLOWED_INFERENCE_LOG_KEYS before a log call, so a future field added to
 * InferenceLogFields without updating the allowlist fails closed (dropped),
 * not open (logged).
 */
export function toSafeInferenceLogFields(fields: InferenceLogFields): Partial<InferenceLogFields> {
  const entries = (Object.entries(fields) as [keyof InferenceLogFields, InferenceLogFields[keyof InferenceLogFields]][])
    .filter(([key]) => ALLOWED_INFERENCE_LOG_KEYS.has(key));
  return Object.fromEntries(entries);
}

export const FORBIDDEN_LOG_FIELD_NAMES = [
  "draft",
  "selectedText",
  "conversation",
  "customInstruction",
  "answers",
  "inlineEnabledProfile",
  "delta",
  "output",
  "brief"
] as const;

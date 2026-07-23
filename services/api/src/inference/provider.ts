import type { InferenceRequestEnvelope, LogicalRoute, WritingAction } from "@writerflow/shared";

/** The server-resolved provider input. Clients never select a model/deployment. */
export interface InferenceProviderRequest {
  action: WritingAction;
  route: LogicalRoute;
  envelope: InferenceRequestEnvelope;
  signal?: AbortSignal;
}

export interface InferenceProviderUsage {
  inputTokens: number;
  outputTokens: number;
}

export interface InferenceStreamResult {
  /** Text deltas, in order. Iterating must never throw for provider-side
   * content issues (e.g. a refusal) — only infrastructure failures
   * (timeout, network) should reject. */
  deltas: AsyncIterable<string>;
  /** Resolves once the full response — and therefore final token counts —
   * is known. Always await this only after fully consuming `deltas`. */
  usage: Promise<InferenceProviderUsage>;
}

export interface InferenceProvider {
  stream(request: InferenceProviderRequest): InferenceStreamResult;
}

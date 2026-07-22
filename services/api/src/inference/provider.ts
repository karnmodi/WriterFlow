/**
 * Stage 5.4 "Server inference endpoint": the seam between the accounting/SSE
 * plumbing in routes/inference.ts and the actual model call. The only
 * implementation today is DevEchoProvider — a real Azure OpenAI-backed one
 * is Stage 5.4's "Azure model plane" work, blocked on user cost approval
 * (phases/phase-5-v2-cloud-foundation.md). Swapping in a real provider later
 * should only mean writing a second class against this interface, not
 * touching the route or accounting code.
 */

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
  fixGrammar(draft: string): InferenceStreamResult;
}

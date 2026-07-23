import type { InferenceProvider, InferenceProviderRequest, InferenceStreamResult } from "./provider.js";

/**
 * Placeholder used until Stage 5.4's real Azure OpenAI model plane is
 * provisioned (blocked on user cost approval — see "Azure model plane" in
 * phases/phase-5-v2-cloud-foundation.md). Does no AI work at all —
 * deterministically collapses redundant whitespace as a stand-in "fix
 * grammar" transform, purely so the accounting/SSE/state-machine plumbing in
 * this vertical slice can be proven end-to-end without spending money or
 * shipping a fake "AI" correction to a real user. Chunks output into a few
 * deltas so callers exercise real streaming, not one big `output.delta`.
 * Must never be reachable in a production deployment once a real provider
 * exists — there is no feature flag disabling it because there is nothing
 * to fall back from yet; index.ts is the only place that constructs it.
 */
export class DevEchoProvider implements InferenceProvider {
  stream(request: InferenceProviderRequest): InferenceStreamResult {
    const draft = request.envelope.content.draft;
    const normalized = draft.replace(/\s+/g, " ").trim();
    const chunkCount = 3;
    const chunkSize = Math.max(1, Math.ceil(normalized.length / chunkCount));
    const chunks: string[] = [];
    for (let i = 0; i < normalized.length; i += chunkSize) {
      chunks.push(normalized.slice(i, i + chunkSize));
    }

    async function* generate(): AsyncGenerator<string> {
      for (const chunk of chunks) {
        // A real provider awaits network I/O per chunk; this microtask hop
        // keeps the interface honestly async without a fake delay.
        await Promise.resolve();
        yield chunk;
      }
    }

    return {
      deltas: generate(),
      usage: Promise.resolve({
        inputTokens: Math.ceil(draft.length / 4),
        outputTokens: Math.ceil(normalized.length / 4)
      })
    };
  }
}

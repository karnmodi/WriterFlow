import { DefaultAzureCredential, type AccessToken } from "@azure/identity";
import type { WritingAction } from "@writerflow/shared";
import { ApiError } from "../errors.js";
import type { InferenceProvider, InferenceProviderRequest, InferenceStreamResult } from "./provider.js";
import type { PromptCompiler } from "./promptCompiler.js";
import { GrammarOutputNormalizer } from "./grammarOutputNormalizer.js";

export interface AzureOpenAIProviderConfig {
  endpoint: string;
  deployment: string;
  apiVersion?: string;
  /**
   * GPT-5 chat-completions reasoning effort. `minimal` keeps light reasoning
   * for clarity without the multi-second silent stall that `low`/`medium`
   * caused on this deployment. Omit only when the deployment is non-reasoning.
   */
  reasoningEffort?: "minimal" | "low" | "medium" | "high";
  /**
   * Ceiling for max_completion_tokens. Per-action caps below this keep
   * rewrite completions short so first visible text stays in the 1–2s band.
   */
  maxCompletionTokens?: number;
}

/** Action-aware completion caps — shorter rewrites finish faster. */
export function maxCompletionTokensForAction(
  action: WritingAction,
  configuredCeiling: number
): number {
  const caps: Record<WritingAction, number> = {
    // `max_completion_tokens` includes hidden reasoning tokens. Keep enough
    // headroom that a short reasoning pass cannot consume the entire budget
    // and leave an empty visible stream.
    fixGrammar: 512,
    formal: 512,
    casual: 512,
    elaborate: 768,
    custom: 768,
    reply: 1_024,
    promptBuilder: 1_024
  };
  return Math.min(configuredCeiling, caps[action]);
}

/**
 * Azure OpenAI streaming provider (Stage 5.4). Managed identity only.
 *
 * Uses Chat Completions against the live `grammar` deployment. The v1 Mac
 * client was fast because it called the Responses API against the user's
 * own gpt-5.4-mini; this subscription only has gpt-5-mini quota, and on that
 * SKU Chat Completions + `reasoning_effort=minimal` is the measured
 * low-latency path (first visible token ~1s warm). Heavier effort values
 * recreate the endless "thinking" spinner.
 */
export class AzureOpenAIProvider implements InferenceProvider {
  private readonly endpoint: string;
  private readonly deployment: string;
  private readonly apiVersion: string;
  private readonly reasoningEffort: "minimal" | "low" | "medium" | "high" | undefined;
  private readonly maxCompletionTokens: number;
  private readonly credential: DefaultAzureCredential;
  private readonly promptCompiler: PromptCompiler;
  private cachedToken: AccessToken | undefined;

  constructor(config: AzureOpenAIProviderConfig, promptCompiler: PromptCompiler) {
    this.endpoint = config.endpoint.replace(/\/$/, "");
    this.deployment = config.deployment;
    this.apiVersion = config.apiVersion ?? "2024-12-01-preview";
    this.reasoningEffort = config.reasoningEffort;
    this.maxCompletionTokens = config.maxCompletionTokens ?? 1024;
    this.promptCompiler = promptCompiler;
    this.credential = new DefaultAzureCredential();
  }

  private async accessToken(): Promise<string> {
    const freshEnoughMs = 60_000;
    if (this.cachedToken && this.cachedToken.expiresOnTimestamp - Date.now() > freshEnoughMs) {
      return this.cachedToken.token;
    }
    const token = await this.credential.getToken("https://cognitiveservices.azure.com/.default");
    // getToken's declared return includes null on some TokenCredential shapes.
    // Fail closed if a credential ever returns an empty/undefined token.
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition -- defensive against credential SDK drift
    if (token == null || !token.token) throw new Error("Azure OpenAI request failed (token)");
    this.cachedToken = token;
    return token.token;
  }

  stream(request: InferenceProviderRequest): InferenceStreamResult {
    const prompt = this.promptCompiler.compile(request);
    const draft = request.envelope.content.draft;
    const url =
      `${this.endpoint}/openai/deployments/${this.deployment}/chat/completions?api-version=${encodeURIComponent(this.apiVersion)}`;
    const maxCompletionTokens = maxCompletionTokensForAction(request.action, this.maxCompletionTokens);
    const reasoningEffort = this.reasoningEffort;
    const getBearer = (): Promise<string> => this.accessToken();

    const body: Record<string, unknown> = {
      messages: [
        { role: "system", content: prompt.system },
        { role: "user", content: prompt.user }
      ],
      stream: true,
      stream_options: { include_usage: true },
      max_completion_tokens: maxCompletionTokens
    };
    if (reasoningEffort) body["reasoning_effort"] = reasoningEffort;

    let usageResolve!: (value: { inputTokens: number; outputTokens: number }) => void;
    let usageReject!: (error: unknown) => void;
    const usage = new Promise<{ inputTokens: number; outputTokens: number }>((resolve, reject) => {
      usageResolve = resolve;
      usageReject = reject;
    });
    void usage.catch(() => undefined);

    async function* deltas(): AsyncGenerator<string> {
      try {
        const bearer = await getBearer();
        const requestInit: RequestInit = {
          method: "POST",
          headers: {
            Authorization: `Bearer ${bearer}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(body)
        };
        requestInit.signal = request.signal
          ? AbortSignal.any([request.signal, AbortSignal.timeout(45_000)])
          : AbortSignal.timeout(45_000);

        let response: Response;
        try {
          response = await fetch(url, requestInit);
        } catch (error) {
          if (request.signal?.aborted) throw error;
          throw new ApiError(
            "MODEL_UNAVAILABLE",
            503,
            "WriterFlow cannot reach the writing model right now. Please try again shortly."
          );
        }
        if (!response.ok || !response.body) {
          const payload = await response.json().catch(() => null) as {
            error?: { code?: string; message?: string; innererror?: { code?: string } };
          } | null;
          const code = payload?.error?.code ?? payload?.error?.innererror?.code ?? "unknown";
          const providerMessage = payload?.error?.message ?? "";
          // Azure saturates with 429 / RateLimitReached — surface as RATE_LIMITED
          // so the Mac preview can show a clear retry message instead of hanging.
          if (response.status === 429 || /rate.?limit|quota|capacity/i.test(code)) {
            throw new ApiError(
              "RATE_LIMITED",
              429,
              "The writing model is at capacity. Please try again in a moment."
            );
          }
          if (response.status === 503) {
            throw new ApiError(
              "MODEL_UNAVAILABLE",
              503,
              "The writing model is temporarily unavailable. Please try again."
            );
          }
          if (
            response.status === 404
            || (response.status === 400
              && /model|deployment|unsupported|reasoning|parameter/i.test(`${code} ${providerMessage}`))
          ) {
            throw new ApiError(
              "MODEL_UNAVAILABLE",
              503,
              "The writing model configuration is temporarily unavailable. Please try again shortly."
            );
          }
          throw new Error(`Azure OpenAI request failed (${response.status}, ${code})`);
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        let inputTokens = Math.ceil(draft.length / 4);
        let outputTokens = 0;
        let gotDelta = false;
        let gotProviderDelta = false;
        const grammarNormalizer = request.action === "fixGrammar"
          ? new GrammarOutputNormalizer(prompt.plan.source)
          : undefined;

        for (;;) {
          const chunk = await reader.read();
          if (chunk.done) break;
          buffer += decoder.decode(chunk.value as Uint8Array, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed.startsWith("data:")) continue;
            const payload = trimmed.slice(5).trim();
            if (!payload || payload === "[DONE]") continue;
            try {
              const parsed = JSON.parse(payload) as {
                choices?: { delta?: { content?: string } }[];
                usage?: { prompt_tokens?: number; completion_tokens?: number };
              };
              const text = parsed.choices?.[0]?.delta?.content;
              if (text) {
                gotProviderDelta = true;
                outputTokens += Math.ceil(text.length / 4);
                const visible = grammarNormalizer?.push(text) ?? text;
                if (visible) {
                  gotDelta = true;
                  yield visible;
                }
              }
              if (parsed.usage?.prompt_tokens != null) inputTokens = parsed.usage.prompt_tokens;
              if (parsed.usage?.completion_tokens != null) {
                outputTokens = parsed.usage.completion_tokens;
              }
            } catch {
              // ignore malformed SSE chunks
            }
          }
        }
        const finalGrammarText = grammarNormalizer?.finish() ?? "";
        if (finalGrammarText) {
          gotDelta = true;
          yield finalGrammarText;
        }
        if (!gotProviderDelta || !gotDelta) {
          throw new ApiError(
            "MODEL_UNAVAILABLE",
            503,
            "The writing model did not produce text. Please try again."
          );
        }
        usageResolve({ inputTokens, outputTokens });
      } catch (error) {
        usageReject(error);
        throw error;
      }
    }

    return { deltas: deltas(), usage };
  }
}

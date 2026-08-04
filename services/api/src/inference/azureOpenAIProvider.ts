import { DefaultAzureCredential, type AccessToken } from "@azure/identity";
import { ApiError } from "../errors.js";
import type { InferenceProvider, InferenceProviderRequest, InferenceStreamResult } from "./provider.js";
import { compilePrompt } from "./promptCompiler.js";

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
  maxCompletionTokens?: number;
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
  private cachedToken: AccessToken | undefined;

  constructor(config: AzureOpenAIProviderConfig) {
    this.endpoint = config.endpoint.replace(/\/$/, "");
    this.deployment = config.deployment;
    this.apiVersion = config.apiVersion ?? "2024-12-01-preview";
    this.reasoningEffort = config.reasoningEffort;
    this.maxCompletionTokens = config.maxCompletionTokens ?? 1024;
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
    const prompt = compilePrompt(request);
    const draft = request.envelope.content.draft;
    const url =
      `${this.endpoint}/openai/deployments/${this.deployment}/chat/completions?api-version=${encodeURIComponent(this.apiVersion)}`;
    const maxCompletionTokens = this.maxCompletionTokens;
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

        const response = await fetch(url, requestInit);
        if (!response.ok || !response.body) {
          const payload = await response.json().catch(() => null) as {
            error?: { code?: string; message?: string; innererror?: { code?: string } };
          } | null;
          const code = payload?.error?.code ?? payload?.error?.innererror?.code ?? "unknown";
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
          throw new Error(`Azure OpenAI request failed (${response.status}, ${code})`);
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        let inputTokens = Math.ceil(draft.length / 4);
        let outputTokens = 0;
        let gotDelta = false;

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
                gotDelta = true;
                outputTokens += Math.ceil(text.length / 4);
                yield text;
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
        if (!gotDelta) {
          throw new Error("Azure OpenAI request failed (empty_stream)");
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

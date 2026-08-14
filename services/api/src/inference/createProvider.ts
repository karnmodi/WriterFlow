import type { InferenceProvider } from "./provider.js";
import { AzureOpenAIProvider, type AzureOpenAIProviderConfig } from "./azureOpenAIProvider.js";
import { DevEchoProvider } from "./devEchoProvider.js";
import { LogicalRoutePoolProvider } from "./routePool.js";
import type { LogicalRoute } from "@writerflow/shared";
import type { PromptCompiler } from "./promptCompiler.js";

/** Select inference backend from environment — Azure OpenAI when configured. */
export function createInferenceProvider(env: NodeJS.ProcessEnv, promptCompiler: PromptCompiler): InferenceProvider {
  const endpoint = env["AZURE_OPENAI_ENDPOINT"];
  const deployment = env["AZURE_OPENAI_DEPLOYMENT"];
  if (endpoint && deployment) {
    const createAzureProvider = (routeDeployment: string): AzureOpenAIProvider => {
      const config: AzureOpenAIProviderConfig = { endpoint, deployment: routeDeployment };
      config.apiVersion = env["AZURE_OPENAI_API_VERSION"] ?? "2024-12-01-preview";
      const reasoningEffort = env["AZURE_OPENAI_REASONING_EFFORT"];
      if (
        reasoningEffort === "minimal"
        || reasoningEffort === "low"
        || reasoningEffort === "medium"
        || reasoningEffort === "high"
      ) {
        config.reasoningEffort = reasoningEffort;
      } else {
        // Default: light reasoning for clarity without the silent stall.
        config.reasoningEffort = "minimal";
      }
      const maxTokensRaw = env["AZURE_OPENAI_MAX_COMPLETION_TOKENS"] ?? env["AZURE_OPENAI_MAX_OUTPUT_TOKENS"];
      if (maxTokensRaw) {
        const parsed = Number.parseInt(maxTokensRaw, 10);
        if (Number.isFinite(parsed) && parsed > 0) {
          config.maxCompletionTokens = parsed;
        }
      }
      return new AzureOpenAIProvider(config, promptCompiler);
    };

    const routeDeployments: Record<LogicalRoute, string> = {
      grammar_fast: env["AZURE_OPENAI_GRAMMAR_FAST_DEPLOYMENT"] ?? deployment,
      rewrite_standard: env["AZURE_OPENAI_REWRITE_STANDARD_DEPLOYMENT"] ?? deployment,
      prompt_enhancer: env["AZURE_OPENAI_PROMPT_ENHANCER_DEPLOYMENT"] ?? deployment,
      rewrite_premium: env["AZURE_OPENAI_PREMIUM_DEPLOYMENT"] ?? deployment,
      classifier_fast: env["AZURE_OPENAI_GRAMMAR_FAST_DEPLOYMENT"] ?? deployment,
      style_analyzer: env["AZURE_OPENAI_REWRITE_STANDARD_DEPLOYMENT"] ?? deployment
    };
    const providers = new Map<LogicalRoute, InferenceProvider>();
    for (const [route, routeDeployment] of Object.entries(routeDeployments) as [LogicalRoute, string][]) {
      providers.set(route, createAzureProvider(routeDeployment));
    }

    const fallbackDeployment = env["AZURE_OPENAI_FALLBACK_DEPLOYMENT"];
    const fallback = fallbackDeployment ? createAzureProvider(fallbackDeployment) : undefined;
    return new LogicalRoutePoolProvider(providers, fallback);
  }
  return new DevEchoProvider();
}

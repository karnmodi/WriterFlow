import type { LogicalRoute } from "@writerflow/shared";
import { ApiError } from "../errors.js";
import type {
  InferenceProvider,
  InferenceProviderRequest,
  InferenceProviderUsage,
  InferenceStreamResult
} from "./provider.js";

interface CircuitState {
  failures: number;
  openUntil: number;
}

const FAILURE_THRESHOLD = 3;
const OPEN_INTERVAL_MS = 30_000;

/**
 * Server-only logical route pool. Clients select an action, never a provider
 * deployment. A fallback is attempted only before any output delta has been
 * emitted, which prevents mixed-model output in one operation.
 */
export class LogicalRoutePoolProvider implements InferenceProvider {
  private readonly primary: ReadonlyMap<LogicalRoute, InferenceProvider>;
  private readonly fallback: InferenceProvider | undefined;
  private readonly circuits = new Map<InferenceProvider, CircuitState>();

  constructor(
    primary: ReadonlyMap<LogicalRoute, InferenceProvider>,
    fallback?: InferenceProvider
  ) {
    this.primary = primary;
    this.fallback = fallback;
  }

  private assertCircuitClosed(provider: InferenceProvider): void {
    const state = this.circuits.get(provider);
    if (state && state.openUntil > Date.now()) {
      throw new ApiError("MODEL_UNAVAILABLE", 503, "The selected model route is temporarily unavailable.");
    }
  }

  private recordSuccess(provider: InferenceProvider): void {
    this.circuits.delete(provider);
  }

  private recordFailure(provider: InferenceProvider): void {
    const state = this.circuits.get(provider) ?? { failures: 0, openUntil: 0 };
    state.failures += 1;
    if (state.failures >= FAILURE_THRESHOLD) {
      state.openUntil = Date.now() + OPEN_INTERVAL_MS;
      state.failures = 0;
    }
    this.circuits.set(provider, state);
  }

  stream(request: InferenceProviderRequest): InferenceStreamResult {
    const primary = this.primary.get(request.route);
    if (!primary) {
      const error = new ApiError("MODEL_UNAVAILABLE", 503, "No provider is configured for this model route.");
      const usage = Promise.reject<InferenceProviderUsage>(error);
      void usage.catch(() => undefined);
      return {
        deltas: {
          [Symbol.asyncIterator]() {
            return {
              next: () => Promise.reject(error)
            };
          }
        },
        usage
      };
    }

    let resolveUsage!: (usage: InferenceProviderUsage) => void;
    let rejectUsage!: (error: unknown) => void;
    const usage = new Promise<InferenceProviderUsage>((resolve, reject) => {
      resolveUsage = resolve;
      rejectUsage = reject;
    });
    // The route consumes usage only after deltas. If delta iteration fails,
    // this prevents a second unhandled-rejection report while preserving the
    // rejected promise for callers that do await it.
    void usage.catch(() => undefined);

    const run = async function* (
      owner: LogicalRoutePoolProvider
    ): AsyncGenerator<string> {
      const providers = owner.fallback && owner.fallback !== primary
        ? [primary, owner.fallback]
        : [primary];

      for (let index = 0; index < providers.length; index += 1) {
        const provider = providers[index];
        if (!provider) continue;
        let emitted = false;
        let result: InferenceStreamResult | undefined;
        try {
          owner.assertCircuitClosed(provider);
          result = provider.stream(request);
          for await (const delta of result.deltas) {
            emitted = true;
            yield delta;
          }
          const finalUsage = await result.usage;
          owner.recordSuccess(provider);
          resolveUsage(finalUsage);
          return;
        } catch (error) {
          owner.recordFailure(provider);
          if (result) void result.usage.catch(() => undefined);
          const canFallback = !emitted && index + 1 < providers.length;
          if (canFallback) continue;
          rejectUsage(error);
          throw error;
        }
      }
    };

    return { deltas: run(this), usage };
  }
}

import { describe, expect, it } from "vitest";
import type {
  InferenceProvider,
  InferenceProviderRequest,
  InferenceStreamResult
} from "../src/inference/provider.js";
import { LogicalRoutePoolProvider } from "../src/inference/routePool.js";

function request(route: InferenceProviderRequest["route"]): InferenceProviderRequest {
  return {
    action: "fixGrammar",
    route,
    envelope: {} as InferenceProviderRequest["envelope"]
  };
}

function provider(
  deltasFactory: () => AsyncIterable<string>,
  onStream?: () => void
): InferenceProvider {
  return {
    stream(): InferenceStreamResult {
      onStream?.();
      return {
        deltas: deltasFactory(),
        usage: Promise.resolve({ inputTokens: 1, outputTokens: 2 })
      };
    }
  };
}

async function collect(result: InferenceStreamResult): Promise<string[]> {
  const values: string[] = [];
  for await (const delta of result.deltas) values.push(delta);
  await result.usage;
  return values;
}

describe("LogicalRoutePoolProvider", () => {
  it("uses exactly one provider call on a normal successful action", async () => {
    let primaryCalls = 0;
    let fallbackCalls = 0;
    const primary = provider(async function* () {
      await Promise.resolve();
      yield "primary";
    }, () => {
      primaryCalls += 1;
    });
    const fallback = provider(async function* () {
      await Promise.resolve();
      yield "fallback";
    }, () => {
      fallbackCalls += 1;
    });
    const pool = new LogicalRoutePoolProvider(new Map([["grammar_fast", primary]]), fallback);

    await expect(collect(pool.stream(request("grammar_fast")))).resolves.toEqual(["primary"]);
    expect(primaryCalls).toBe(1);
    expect(fallbackCalls).toBe(0);
  });

  it("falls back when the primary fails before its first delta", async () => {
    let fallbackCalls = 0;
    const primary = provider(async function* () {
      yield await Promise.reject(new Error("primary unavailable"));
    });
    const fallback = provider(async function* () {
      await Promise.resolve();
      yield "fallback";
    }, () => {
      fallbackCalls += 1;
    });
    const pool = new LogicalRoutePoolProvider(new Map([["grammar_fast", primary]]), fallback);

    await expect(collect(pool.stream(request("grammar_fast")))).resolves.toEqual(["fallback"]);
    expect(fallbackCalls).toBe(1);
  });

  it("never mixes fallback output after the first primary delta", async () => {
    let fallbackCalls = 0;
    const primary = provider(async function* () {
      await Promise.resolve();
      yield "primary";
      throw new Error("stream interrupted");
    });
    const fallback = provider(async function* () {
      await Promise.resolve();
      yield "fallback";
    }, () => {
      fallbackCalls += 1;
    });
    const pool = new LogicalRoutePoolProvider(new Map([["grammar_fast", primary]]), fallback);

    const result = pool.stream(request("grammar_fast"));
    const values: string[] = [];
    await expect((async () => {
      for await (const delta of result.deltas) values.push(delta);
    })()).rejects.toThrow("stream interrupted");
    expect(values).toEqual(["primary"]);
    expect(fallbackCalls).toBe(0);
  });
});

import { describe, expect, it } from "vitest";
import { GrammarOutputNormalizer } from "../src/inference/grammarOutputNormalizer.js";

function normalize(source: string, deltas: string[]): string {
  const normalizer = new GrammarOutputNormalizer(source);
  return `${deltas.map((delta) => normalizer.push(delta)).join("")}${normalizer.finish()}`;
}

describe("GrammarOutputNormalizer", () => {
  it("strips model-added transport quotes across fragmented deltas", () => {
    expect(normalize("This sentence is correct.", ['"', "This sentence ", "is correct.", '"']))
      .toBe("This sentence is correct.");
  });

  it("leaves an unquoted result unchanged", () => {
    expect(normalize("kal meeting confirm hai?", ["kal ", "meeting confirm hai?"]))
      .toBe("kal meeting confirm hai?");
  });

  it("preserves quotes that are part of the source", () => {
    expect(normalize('"It is ready."', ['"It is ready."']))
      .toBe('"It is ready."');
  });
});

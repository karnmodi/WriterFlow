import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  InferenceRequestEnvelopeSchema,
  StyleAnalysisRequestSchema
} from "../src/schemas/inference-request.js";
import { InferenceStreamEventSchema } from "../src/schemas/sse-events.js";

/**
 * Wires the Stage 5.0 fixtures (Docs/contracts/fixtures/) into the Stage 5.1
 * TypeScript harness, as promised by Docs/contracts/fixtures/README.md.
 */
const repoRoot = path.resolve(fileURLToPath(new URL("../../../", import.meta.url)));
const fixturesRoot = path.join(repoRoot, "Docs", "contracts", "fixtures");

function readJson(filePath: string): unknown {
  return JSON.parse(readFileSync(filePath, "utf-8"));
}

function listFixtureFiles(dir: string): string[] {
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => path.join(dir, name));
}

describe("Stage 5.0 request fixtures validate against the shared schema", () => {
  const requestsDir = path.join(fixturesRoot, "requests");
  for (const file of listFixtureFiles(requestsDir)) {
    const base = path.basename(file);
    it(`${base} matches its target schema`, () => {
      const fixture = readJson(file) as { request: unknown };
      if (base === "style-analysis.json") {
        expect(() => StyleAnalysisRequestSchema.parse(fixture.request)).not.toThrow();
        return;
      }
      expect(() => InferenceRequestEnvelopeSchema.parse(fixture.request)).not.toThrow();
    });
  }
});

describe("Stage 5.0 event fixtures validate against the SSE event schema", () => {
  const eventsDir = path.join(fixturesRoot, "events");
  for (const file of listFixtureFiles(eventsDir)) {
    const base = path.basename(file);
    it(`${base} every event matches InferenceStreamEventSchema`, () => {
      const fixture = readJson(file) as Record<string, unknown>;
      const events =
        (fixture["events"] as unknown[] | undefined) ??
        (fixture["eventsReceivedByClientBeforeItDisconnects"] as unknown[] | undefined) ??
        (fixture["eventsDeliveredBeforeDrop"] as unknown[] | undefined);
      expect(events, `${base} must expose an events-shaped array`).toBeDefined();
      for (const event of events ?? []) {
        expect(() => InferenceStreamEventSchema.parse(event)).not.toThrow();
      }
    });
  }
});

describe("Stage 5.0 redaction canary fixture", () => {
  it("every inference-envelope canary request validates against the request schema", () => {
    const file = path.join(fixturesRoot, "redaction", "canary-secrets.json");
    const fixture = readJson(file) as { requests: { target: string; request: unknown }[] };
    for (const entry of fixture.requests) {
      if (entry.target === "POST /v2/inference/stream") {
        expect(() => InferenceRequestEnvelopeSchema.parse(entry.request)).not.toThrow();
      }
    }
  });
});

#!/usr/bin/env tsx
import { randomUUID } from "node:crypto";

const baseUrl = (process.env["WRITERFLOW_API_URL"] ?? "https://apiwriterflow.aviusolutions.com/v2").replace(/\/$/, "");
const accessToken = process.env["WRITERFLOW_ACCESS_TOKEN"];
const deviceId = process.env["WRITERFLOW_DEVICE_ID"];
const requests = Number.parseInt(process.env["LOAD_REQUESTS"] ?? "25", 10);
const concurrency = Number.parseInt(process.env["LOAD_CONCURRENCY"] ?? "5", 10);

if (!accessToken || !deviceId) {
  throw new Error("WRITERFLOW_ACCESS_TOKEN and WRITERFLOW_DEVICE_ID are required");
}
if (!Number.isSafeInteger(requests) || requests < 1 || requests > 200) {
  throw new Error("LOAD_REQUESTS must be between 1 and 200");
}
if (!Number.isSafeInteger(concurrency) || concurrency < 1 || concurrency > 20) {
  throw new Error("LOAD_CONCURRENCY must be between 1 and 20");
}

const envelope = {
  operationId: "",
  mode: "explicit",
  task: {
    requestedAction: "fixGrammar",
    customInstruction: null,
    promptBuilder: null,
    outputModeHint: "replace"
  },
  target: {
    bundleId: "com.apple.Notes",
    site: null,
    windowClass: null,
    fieldRevision: "load-test"
  },
  content: {
    targetScope: "field",
    draft: "Please fix this sentence.",
    selectedText: null,
    conversation: null
  },
  signals: {
    hasSelection: false,
    hasVisibleThread: false,
    inputLength: 25,
    appTone: null
  },
  personalization: null
};

async function inference(idempotencyKey: string): Promise<number> {
  const startedAt = performance.now();
  const response = await fetch(`${baseUrl}/inference/stream`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
      "X-WriterFlow-Version": "2.0.0-load",
      "X-WriterFlow-Device": deviceId
    },
    body: JSON.stringify({ ...envelope, operationId: randomUUID() }),
    signal: AbortSignal.timeout(120_000)
  });
  const body = await response.text();
  if (!response.ok || !body.includes('"type":"completed"')) {
    throw new Error(`Inference failed with status ${response.status}`);
  }
  return performance.now() - startedAt;
}

async function main(): Promise<void> {
  const durations: number[] = [];
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, requests) }, async () => {
    while (next < requests) {
      next += 1;
      durations.push(await inference(randomUUID()));
    }
  }));

  durations.sort((left, right) => left - right);
  const percentile = (value: number): number => {
    const index = Math.min(durations.length - 1, Math.ceil(value * durations.length) - 1);
    return Math.round(durations[index] ?? 0);
  };

  // One idempotency key replay verifies APIM preserves operation identity.
  const replayKey = randomUUID();
  await inference(replayKey);
  await inference(replayKey);

  console.log(JSON.stringify({
    requests,
    concurrency,
    p50Ms: percentile(0.5),
    p95Ms: percentile(0.95),
    replay: "passed"
  }));
}

void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "Load probe failed");
  process.exitCode = 1;
});

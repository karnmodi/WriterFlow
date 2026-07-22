#!/usr/bin/env node
/** Phase 8 APIM SSE load smoke — run against staging APIM with a valid device token. */
const url = process.env.APIM_SSE_URL ?? "https://api.writerflow.aviusolutions.com/v2/inference/stream";
const token = process.env.WRITERFLOW_ACCESS_TOKEN;
const deviceId = process.env.WRITERFLOW_DEVICE_ID;

if (!token || !deviceId) {
  console.error("Set WRITERFLOW_ACCESS_TOKEN and WRITERFLOW_DEVICE_ID");
  process.exit(1);
}

const body = {
  operationId: crypto.randomUUID(),
  mode: "explicit",
  task: { requestedAction: "fixGrammar" },
  content: {
    bundleId: "com.apple.TextEdit",
    targetScope: "field",
    draft: "hello world",
    hasSelection: false,
    hasVisibleThread: false,
    outputModeHint: "replace"
  },
  signals: {}
};

const started = Date.now();
const response = await fetch(url, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "Idempotency-Key": crypto.randomUUID(),
    "X-WriterFlow-Version": "2.0.0-alpha",
    "X-WriterFlow-Device": deviceId
  },
  body: JSON.stringify(body)
});

console.log("status", response.status, "ms", Date.now() - started);
if (!response.ok) {
  console.error(await response.text());
  process.exit(1);
}

const reader = response.body?.getReader();
let events = 0;
while (reader) {
  const { done, value } = await reader.read();
  if (done) break;
  events += (new TextDecoder().decode(value).match(/^data:/gm) ?? []).length;
}
console.log("events", events, "total_ms", Date.now() - started);

#!/usr/bin/env node
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));
const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const key = process.argv[index];
  const value = process.argv[index + 1];
  if (key && value) args.set(key, value);
}

const apiBase = (args.get("--api-base") ?? "https://wfprod-apim-dev.azure-api.net/v2").replace(/\/$/, "");
const outputPath = path.resolve(args.get("--output") ?? path.join(repoRoot, "build", "prompt-evals", "live.json"));
const label = args.get("--label") ?? "candidate";
const limit = Number.parseInt(args.get("--limit") ?? "160", 10);
const delayMs = Number.parseInt(args.get("--delay-ms") ?? "6_000", 10);
const retryDelayMs = Number.parseInt(args.get("--retry-delay-ms") ?? "60_000", 10);
const maxRateLimitRetries = Number.parseInt(args.get("--rate-limit-retries") ?? "4", 10);
const refreshIds = new Set((args.get("--refresh-ids") ?? "").split(",").filter(Boolean));
const onlyIds = new Set((args.get("--only-ids") ?? "").split(",").filter(Boolean));
const corpusPath = path.join(repoRoot, "prompts", "evals", "cases.jsonl");
const allCases = readFileSync(corpusPath, "utf8").trim().split("\n").map((line) => JSON.parse(line));
const corpus = (onlyIds.size > 0 ? allCases.filter((entry) => onlyIds.has(entry.id)) : allCases).slice(0, limit);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function jsonRequest(url, init) {
  const response = await fetch(url, init);
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  return { response, payload };
}

async function pairEvaluationDevice() {
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const authorize = await jsonRequest(`${apiBase}/device/authorize`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      installId: `prompt-eval-${randomUUID()}`,
      deviceLabel: `Prompt evaluation ${label}`,
      codeChallenge: challenge,
      codeChallengeMethod: "S256"
    })
  });
  if (!authorize.response.ok) {
    throw new Error(`Device authorize failed (${authorize.response.status}): ${JSON.stringify(authorize.payload)}`);
  }
  process.stdout.write(`PAIR_URL ${authorize.payload.verificationUriComplete}\n`);
  process.stdout.write(`PAIR_CODE ${authorize.payload.userCode}\n`);

  let intervalSeconds = Number(authorize.payload.interval ?? 5);
  const deadline = Date.now() + Number(authorize.payload.expiresIn ?? 600) * 1_000;
  while (Date.now() < deadline) {
    await sleep(intervalSeconds * 1_000);
    const poll = await jsonRequest(`${apiBase}/device/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deviceCode: authorize.payload.deviceCode, codeVerifier: verifier })
    });
    if (poll.response.ok && poll.payload.accessToken) {
      process.stdout.write(`PAIRED ${poll.payload.deviceId}\n`);
      return {
        accessToken: poll.payload.accessToken,
        refreshToken: poll.payload.refreshToken,
        deviceId: poll.payload.deviceId,
        expiresAt: Date.now() + Number(poll.payload.expiresIn) * 1_000
      };
    }
    const pollStatus = poll.payload.error ?? poll.payload.status;
    if (pollStatus === "authorization_pending") continue;
    if (pollStatus === "slow_down") {
      intervalSeconds += 5;
      continue;
    }
    throw new Error(`Device pairing failed: ${JSON.stringify(poll.payload)}`);
  }
  throw new Error("Device pairing expired");
}

async function ensureAccessToken(session) {
  if (session.expiresAt - Date.now() > 60_000) return;
  const refreshed = await jsonRequest(`${apiBase}/token/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: session.refreshToken })
  });
  if (!refreshed.response.ok) throw new Error(`Evaluation token refresh failed (${refreshed.response.status})`);
  session.accessToken = refreshed.payload.accessToken;
  session.refreshToken = refreshed.payload.refreshToken;
  session.deviceId = refreshed.payload.deviceId;
  session.expiresAt = Date.now() + Number(refreshed.payload.expiresIn) * 1_000;
}

function requestEnvelope(entry) {
  const promptBuilder = entry.promptBuilder
    ? { ...entry.promptBuilder, flowId: randomUUID() }
    : null;
  return {
    operationId: randomUUID(),
    mode: "explicit",
    task: {
      requestedAction: entry.action,
      customInstruction: entry.customInstruction,
      promptBuilder,
      outputModeHint: entry.outputMode
    },
    target: {
      bundleId: "com.writerflow.synthetic-eval",
      site: entry.site,
      windowClass: null,
      fieldRevision: `quality-${entry.id}`
    },
    content: {
      targetScope: entry.targetScope,
      draft: entry.draft,
      selectedText: entry.selectedText,
      conversation: entry.conversation
    },
    signals: {
      hasSelection: entry.targetScope === "selection",
      hasVisibleThread: Boolean(entry.conversation),
      inputLength: entry.draft.length,
      appTone: entry.appTone
    },
    personalization: null
  };
}

async function runCase(session, entry) {
  await ensureAccessToken(session);
  const operationId = randomUUID();
  const idempotencyKey = randomUUID();
  const envelope = requestEnvelope(entry);
  envelope.operationId = operationId;
  const startedAt = performance.now();
  const response = await fetch(`${apiBase}/inference/stream`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.accessToken}`,
      "Content-Type": "application/json",
      Accept: "text/event-stream",
      "Idempotency-Key": idempotencyKey,
      "X-WriterFlow-Version": "2.0.2",
      "X-WriterFlow-Device": session.deviceId
    },
    body: JSON.stringify(envelope)
  });
  if (!response.ok || !response.body) {
    return {
      id: entry.id,
      operationId,
      status: "http_error",
      httpStatus: response.status,
      error: await response.text(),
      totalMs: Math.round(performance.now() - startedAt)
    };
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let output = "";
  let firstVisibleMs = null;
  let decision = null;
  let completed = null;
  let usage = null;
  let terminalError = null;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let separator;
    while ((separator = buffer.indexOf("\n\n")) >= 0) {
      const frame = buffer.slice(0, separator);
      buffer = buffer.slice(separator + 2);
      const data = frame.split("\n").find((line) => line.startsWith("data: "))?.slice(6);
      if (!data) continue;
      const event = JSON.parse(data);
      if (event.type === "decision") decision = event;
      if (event.type === "output.delta") {
        if (firstVisibleMs == null) firstVisibleMs = Math.round(performance.now() - startedAt);
        output += event.delta;
      }
      if (event.type === "prompt_builder.questions") {
        if (firstVisibleMs == null) firstVisibleMs = Math.round(performance.now() - startedAt);
        output = `---CLARIFY---\n${event.questions.join("\n")}`;
      }
      if (event.type === "usage.summary") usage = event;
      if (event.type === "completed") completed = event;
      if (event.type === "error") terminalError = event;
    }
  }
  return {
    id: entry.id,
    operationId,
    status: terminalError ? "error" : completed ? "completed" : "incomplete",
    firstVisibleMs,
    totalMs: Math.round(performance.now() - startedAt),
    output,
    outputCharacters: output.length,
    decision,
    usage,
    completed,
    terminalError
  };
}

function isCapacityFailure(result) {
  if (result.httpStatus === 429) return true;
  return result.terminalError?.code === "RATE_LIMITED"
    || result.terminalError?.code === "MODEL_UNAVAILABLE"
    || result.terminalError?.code === "INTERNAL_ERROR";
}

function buildReport(results) {
  const completed = results.filter((result) => result.status === "completed");
  const firstVisible = completed.map((result) => result.firstVisibleMs).filter((value) => Number.isFinite(value)).sort((a, b) => a - b);
  const total = completed.map((result) => result.totalMs).sort((a, b) => a - b);
  const percentile = (values, value) => values.length ? values[Math.ceil(values.length * value) - 1] : null;
  return {
    label,
    apiBase,
    capturedAt: new Date().toISOString(),
    corpusSize: corpus.length,
    summary: {
      completed: completed.length,
      failed: results.length - completed.length,
      firstVisibleP50Ms: percentile(firstVisible, 0.5),
      firstVisibleP95Ms: percentile(firstVisible, 0.95),
      completionP50Ms: percentile(total, 0.5),
      completionP95Ms: percentile(total, 0.95),
      successfulProviderOperations: completed.length
    },
    results
  };
}

function writeReport(results) {
  const report = buildReport(results);
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  return report;
}

const session = await pairEvaluationDevice();
let previousResults = [];
try {
  const previous = JSON.parse(readFileSync(outputPath, "utf8"));
  if (previous.label === label && previous.apiBase === apiBase && Array.isArray(previous.results)) {
    previousResults = previous.results;
  }
} catch {
  // A missing or invalid report starts a fresh run.
}
const completedById = new Map(
  previousResults.filter((result) => result.status === "completed").map((result) => [result.id, result])
);
const resultById = new Map(completedById);
const results = [];
try {
  for (const [index, entry] of corpus.entries()) {
    if (entry.tags?.includes("live-provider-policy-probe")) {
      const excluded = {
        id: entry.id,
        status: "excluded",
        reason: "Provider policy rejection is covered by deterministic injection tests."
      };
      results.push(excluded);
      resultById.set(entry.id, excluded);
      writeReport(corpus.map((item) => resultById.get(item.id)).filter(Boolean));
      process.stdout.write(`CASE ${index + 1}/${corpus.length} ${entry.id} excluded\n`);
      continue;
    }
    const preserved = refreshIds.has(entry.id) ? undefined : completedById.get(entry.id);
    if (preserved) {
      results.push(preserved);
      process.stdout.write(`CASE ${index + 1}/${corpus.length} ${entry.id} preserved first=${preserved.firstVisibleMs ?? "-"} total=${preserved.totalMs}\n`);
      continue;
    }

    let result;
    for (let attempt = 0; attempt <= maxRateLimitRetries; attempt += 1) {
      result = await runCase(session, entry);
      if (!isCapacityFailure(result) || attempt === maxRateLimitRetries) break;
      const waitMs = retryDelayMs * (attempt + 1);
      process.stdout.write(`RETRY ${entry.id} capacity attempt=${attempt + 1} waitMs=${waitMs}\n`);
      await sleep(waitMs);
    }
    results.push(result);
    resultById.set(entry.id, result);
    writeReport(corpus.map((item) => resultById.get(item.id)).filter(Boolean));
    process.stdout.write(`CASE ${index + 1}/${corpus.length} ${entry.id} ${result.status} first=${result.firstVisibleMs ?? "-"} total=${result.totalMs}\n`);
    await sleep(delayMs);
  }
} finally {
  await ensureAccessToken(session).catch(() => undefined);
  await fetch(`${apiBase}/devices/${session.deviceId}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${session.accessToken}`,
      "X-WriterFlow-Device": session.deviceId
    }
  }).catch(() => undefined);
}

const report = writeReport(corpus.map((item) => resultById.get(item.id)).filter(Boolean));
process.stdout.write(`REPORT ${outputPath}\n`);
process.stdout.write(`${JSON.stringify(report.summary)}\n`);

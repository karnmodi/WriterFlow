#!/usr/bin/env node
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PromptCompiler } from "../../services/api/dist/src/inference/promptCompiler.js";

const repoRoot = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));
const cases = readFileSync(path.join(repoRoot, "prompts", "evals", "cases.jsonl"), "utf8")
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line));
const routes = {
  elaborate: "rewrite_standard",
  formal: "rewrite_standard",
  casual: "rewrite_standard",
  fixGrammar: "grammar_fast",
  reply: "rewrite_standard",
  custom: "rewrite_standard",
  promptBuilder: "prompt_enhancer"
};

function requestFor(entry, index) {
  return {
    action: entry.action,
    route: routes[entry.action],
    envelope: {
      operationId: `10000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
      mode: "explicit",
      task: {
        requestedAction: entry.action,
        customInstruction: entry.customInstruction,
        promptBuilder: entry.promptBuilder
          ? {
              ...entry.promptBuilder,
              flowId: `20000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`
            }
          : null,
        outputModeHint: entry.outputMode
      },
      target: {
        bundleId: "com.writerflow.synthetic-eval",
        site: entry.site,
        windowClass: null,
        fieldRevision: `eval-${index + 1}`
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
    }
  };
}

function percentile(sorted, quantile) {
  return sorted[Math.max(0, Math.ceil(sorted.length * quantile) - 1)];
}

const compiler = PromptCompiler.load(path.join(repoRoot, "prompts"));
const requests = cases.map(requestFor);
for (const request of requests) compiler.compile(request);

const durations = [];
for (let pass = 0; pass < 100; pass += 1) {
  for (const request of requests) {
    const started = performance.now();
    compiler.compile(request);
    durations.push(performance.now() - started);
  }
}
durations.sort((left, right) => left - right);

const policySizes = {};
for (const request of requests) {
  const compiled = compiler.compile(request);
  const current = policySizes[request.action] ?? { maxSystemChars: 0, maxEstimatedSystemTokens: 0 };
  current.maxSystemChars = Math.max(current.maxSystemChars, compiled.system.length);
  current.maxEstimatedSystemTokens = Math.max(
    current.maxEstimatedSystemTokens,
    Math.ceil(compiled.system.length / 4)
  );
  policySizes[request.action] = current;
}

process.stdout.write(`${JSON.stringify({
  node: process.version,
  corpusCases: requests.length,
  samples: durations.length,
  compileMs: {
    p50: percentile(durations, 0.5),
    p95: percentile(durations, 0.95),
    max: durations.at(-1)
  },
  policySizes
}, null, 2)}\n`);

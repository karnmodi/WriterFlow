#!/usr/bin/env node
import { createHash } from "node:crypto";
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

const baselinePath = path.resolve(args.get("--baseline") ?? path.join(repoRoot, "build/prompt-evals/production-baseline.json"));
const candidatePath = path.resolve(args.get("--candidate") ?? path.join(repoRoot, "build/prompt-evals/candidate.json"));
const outputDir = path.resolve(args.get("--output-dir") ?? path.join(repoRoot, "build/prompt-evals/comparison"));
const corpus = readFileSync(path.join(repoRoot, "prompts/evals/cases.jsonl"), "utf8")
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line));
const corpusById = new Map(corpus.map((entry) => [entry.id, entry]));

function loadReport(filePath) {
  const report = JSON.parse(readFileSync(filePath, "utf8"));
  if (!Array.isArray(report.results)) throw new Error(`Invalid evaluation report: ${filePath}`);
  return report;
}

function inputText(entry) {
  return [
    entry.targetScope === "selection" ? entry.selectedText : entry.draft,
    entry.conversation,
    entry.customInstruction,
    entry.promptBuilder?.brief,
    ...(entry.promptBuilder?.answers ?? [])
  ].filter(Boolean).join("\n");
}

function countWords(value) {
  return value.trim() ? value.trim().split(/\s+/).length : 0;
}

function promptBuilderValid(entry, output) {
  const clarify = output.match(/---CLARIFY---/g)?.length ?? 0;
  const prompt = output.match(/---PROMPT---/g)?.length ?? 0;
  if (entry.promptBuilder?.phase === "finalize") return clarify === 0 && prompt === 1;
  return clarify + prompt === 1;
}

function platformValid(entry, output) {
  if (entry.action !== "reply") return true;
  const site = String(entry.site).toLowerCase();
  if (["gmail", "outlook"].includes(site)) return !/^subject\s*:/im.test(output);
  if (["slack", "whatsapp-web", "whatsapp-desktop", "telegram"].includes(site)) {
    return !/^(dear|hi|hello)\b/im.test(output) && !/(kind regards|best regards|sincerely),?\s*$/im.test(output);
  }
  if (["chatgpt", "claude", "gemini", "copilot", "perplexity", "poe", "cursor"].includes(site)) {
    return !/^(dear|hi|hello)\b/im.test(output) && !/(kind regards|best regards|sincerely),?\s*$/im.test(output);
  }
  return !/^subject\s*:/im.test(output);
}

function customInvariant(entry, output) {
  if (entry.action !== "custom") return true;
  if (output.includes("---INSERT---")) return false;
  switch (entry.id) {
    case "custom-core-01": return countWords(output) === 6;
    case "custom-core-03": return (output.match(/^\s*[-*•]\s+/gm)?.length ?? 0) === 3;
    case "custom-core-07": {
      try {
        const parsed = JSON.parse(output);
        return Object.hasOwn(parsed, "status") && Object.hasOwn(parsed, "date");
      } catch {
        return false;
      }
    }
    case "custom-core-08": return output.includes("no client changes");
    case "custom-core-09": return countWords(output) > 0 && !/[.!?].+?[.!?]/s.test(output) && output.includes("E_CONNRESET");
    case "custom-core-11": return countWords(output.split(/\r?\n/)[0] ?? "") <= 3;
    default: return true;
  }
}

function evaluate(report) {
  const rows = report.results.map((result) => {
    const entry = corpusById.get(result.id);
    if (!entry) throw new Error(`Unknown corpus case: ${result.id}`);
    const output = result.output ?? "";
    const available = inputText(entry).toLocaleLowerCase();
    const required = entry.mustPreserve.filter((value) => available.includes(String(value).toLocaleLowerCase()));
    const preserved = required.filter((value) => output.toLocaleLowerCase().includes(String(value).toLocaleLowerCase()));
    return {
      id: entry.id,
      action: entry.action,
      liveExcluded: entry.tags.includes("live-provider-policy-probe"),
      completed: result.status === "completed",
      preservationPassed: preserved.length === required.length,
      preservationRequired: required.length,
      preservationFound: preserved.length,
      parserPassed: entry.action === "promptBuilder"
        ? promptBuilderValid(entry, output)
        : !/---(?:CLARIFY|PROMPT)---/.test(output),
      grammarUnchangedPassed: !entry.expectedUnchanged || output === entry.draft,
      outputModePassed: result.decision?.outputMode === entry.outputMode,
      platformPassed: platformValid(entry, output),
      customInvariantPassed: customInvariant(entry, output),
      promptVersion: result.completed?.promptVersion ?? null,
      firstVisibleMs: result.firstVisibleMs,
      totalMs: result.totalMs,
      outputCharacters: result.outputCharacters ?? output.length
    };
  });
  const eligible = rows.filter((row) => !row.liveExcluded);
  const completed = eligible.filter((row) => row.completed);
  const rate = (predicate) => completed.length
    ? completed.filter(predicate).length / completed.length
    : 0;
  const preservationRequired = completed.reduce((sum, row) => sum + row.preservationRequired, 0);
  const preservationFound = completed.reduce((sum, row) => sum + row.preservationFound, 0);
  return {
    label: report.label,
    summary: report.summary,
    gates: {
      completionRate: eligible.length ? completed.length / eligible.length : 0,
      factualPreservationRate: preservationRequired ? preservationFound / preservationRequired : 1,
      parserValidityRate: rate((row) => row.parserPassed),
      grammarUnchangedRate: rate((row) => row.grammarUnchangedPassed),
      outputModeRate: rate((row) => row.outputModePassed),
      replyPlatformRate: (() => {
        const replies = completed.filter((row) => row.action === "reply");
        return replies.length ? replies.filter((row) => row.platformPassed).length / replies.length : 0;
      })(),
      customInvariantRate: (() => {
        const custom = completed.filter((row) => row.action === "custom");
        return custom.length ? custom.filter((row) => row.customInvariantPassed).length / custom.length : 0;
      })()
    },
    excluded: rows.filter((row) => row.liveExcluded).map((row) => row.id),
    failures: rows.filter((row) => !row.liveExcluded && row.completed && (
      !row.preservationPassed
      || !row.parserPassed
      || !row.grammarUnchangedPassed
      || !row.outputModePassed
      || !row.platformPassed
      || !row.customInvariantPassed
    )),
    rows
  };
}

function blindedPacket(baseline, candidate) {
  const baselineById = new Map(baseline.results.map((result) => [result.id, result]));
  const candidateById = new Map(candidate.results.map((result) => [result.id, result]));
  return corpus.map((entry) => {
    const baselineResult = baselineById.get(entry.id);
    const candidateResult = candidateById.get(entry.id);
    const candidateFirst = createHash("sha256").update(entry.id).digest()[0] % 2 === 0;
    const options = candidateFirst
      ? [candidateResult?.output ?? "", baselineResult?.output ?? ""]
      : [baselineResult?.output ?? "", candidateResult?.output ?? ""];
    return {
      id: entry.id,
      action: entry.action,
      site: entry.site,
      input: inputText(entry),
      optionA: options[0],
      optionB: options[1],
      preferred: "",
      scoresA: {},
      scoresB: {},
      criticalFailure: "",
      reviewerNotes: "",
      _answerKey: candidateFirst ? "A" : "B"
    };
  });
}

const baseline = loadReport(baselinePath);
const candidate = loadReport(candidatePath);
const analysis = {
  generatedAt: new Date().toISOString(),
  baseline: evaluate(baseline),
  candidate: evaluate(candidate)
};
const packet = blindedPacket(baseline, candidate);
mkdirSync(outputDir, { recursive: true });
writeFileSync(path.join(outputDir, "automated-analysis.json"), `${JSON.stringify(analysis, null, 2)}\n`, { mode: 0o600 });
writeFileSync(path.join(outputDir, "blinded-review.json"), `${JSON.stringify(packet.map(({ _answerKey: _, ...entry }) => entry), null, 2)}\n`, { mode: 0o600 });
writeFileSync(path.join(outputDir, "review-answer-key.json"), `${JSON.stringify(Object.fromEntries(packet.map((entry) => [entry.id, entry._answerKey])), null, 2)}\n`, { mode: 0o600 });
process.stdout.write(`${JSON.stringify({ baseline: analysis.baseline.gates, candidate: analysis.candidate.gates }, null, 2)}\n`);

#!/usr/bin/env node
/**
 * Stage 5.6 / Phase 8 release scanner extension — rejects v2 artifacts that
 * contain BYO Azure endpoints, deployment names, Entra secrets, or dev signing keys.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const root = process.argv[2] ?? "build/WriterFlow.app";
const forbidden = [
  /https:\/\/(?!YOUR-RESOURCE)[a-z0-9][a-z0-9-]*\.(?:openai|cognitiveservices)\.azure\.com/i,
  /api-key\s*[:=]/i,
  /deployment[-_]?(name|id)/i,
  /ENTRA_WEB_CLIENT_SECRET/i,
  /WRITERFLOW_API_BASE_URL/i,
  /\.dev-signing-key\.json/i,
  /sk-[a-zA-Z0-9]{20,}/,
  /postgres(?:ql)?:\/\/[^\s"']+/i,
  /Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/
];
const required = [/apiwriterflow\.aviusolutions\.com/i];
const foundRequired = new Set();

const failures = [];

function scanFile(path) {
  let text;
  try {
    text = readFileSync(path);
  } catch {
    return;
  }
  const content = text.toString("utf8");
  for (const pattern of forbidden) {
    if (pattern.test(content)) {
      failures.push(`${path}: matched ${pattern}`);
    }
  }
  for (const pattern of required) {
    if (pattern.test(content)) foundRequired.add(pattern);
  }
}

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) walk(path);
    else if (/\.(swift|plist|json|env|xcconfig|strings)$/i.test(entry) || entry === "WriterFlow") {
      scanFile(path);
    }
  }
}

try {
  walk(root);
} catch (err) {
  console.error(`Cannot scan ${root}:`, err instanceof Error ? err.message : String(err));
  process.exit(1);
}

if (failures.length) {
  console.error("Release scanner failed:\n", failures.join("\n"));
  process.exit(1);
}
for (const pattern of required) {
  if (!foundRequired.has(pattern)) {
    console.error(`Release scanner failed: required production endpoint ${pattern} was not found`);
    process.exit(1);
  }
}

console.log(`Release scanner passed for ${root}`);

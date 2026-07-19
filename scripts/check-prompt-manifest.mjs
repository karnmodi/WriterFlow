#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { load } from "js-yaml";

/**
 * Confirms every asset path prompts/manifest.yaml declares actually exists
 * on disk, so a typo'd or removed prompt file fails CI instead of a runtime
 * 404/fallback (Stage 5.1 "prompt-resource integrity checks").
 *
 * Only checks values under known path-bearing keys — not every string in
 * the manifest (many, like `note`/`usedBy`, are prose or action-name lists,
 * not paths).
 */
const PATH_KEYS = new Set([
  "path",
  "cases",
  "decision",
  "contextualTransform",
  "continuationSite",
  "replyFormat",
  "modeVariants",
  "outputFormatVariants"
]);

const promptsRoot = path.resolve(import.meta.dirname, "..", "prompts");
const manifestPath = path.join(promptsRoot, "manifest.yaml");
const manifest = load(readFileSync(manifestPath, "utf8"));

const missing = [];
const checked = [];

function walk(node) {
  if (Array.isArray(node)) {
    for (const item of node) walk(item);
    return;
  }
  if (node && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      if (PATH_KEYS.has(key) && typeof value === "string") {
        const target = path.join(promptsRoot, value);
        checked.push(value);
        if (!existsSync(target)) {
          missing.push(value);
        }
      } else {
        walk(value);
      }
    }
  }
}

walk(manifest);

if (missing.length > 0) {
  console.error(`FAIL: ${missing.length} manifest path(s) do not exist on disk:`);
  for (const m of missing) console.error(`  - prompts/${m}`);
  process.exit(1);
}

console.log(`OK: all ${checked.length} prompts/manifest.yaml path references exist on disk.`);

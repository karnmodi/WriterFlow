#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { load } from "js-yaml";

const [, , filePath] = process.argv;
if (!filePath) {
  console.error("usage: check-yaml.mjs <file.yaml>");
  process.exit(1);
}

try {
  load(readFileSync(filePath, "utf8"));
  console.log(`OK: ${filePath} is valid YAML`);
} catch (err) {
  console.error(`FAIL: ${filePath} is not valid YAML`);
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}

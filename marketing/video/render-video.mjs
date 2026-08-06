import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs/promises";

const require = createRequire(import.meta.url);
const { chromium } = require(
  "/Users/karan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright"
);
const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.join(here, "render");
await fs.rm(output, { recursive: true, force: true });
await fs.mkdir(output, { recursive: true });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 3840, height: 2160 },
  recordVideo: { dir: output, size: { width: 3840, height: 2160 } },
});
const page = await context.newPage();
await page.goto(pathToFileURL(path.join(here, "writerflow-ad.html")).href);
await page.evaluate(() => {
  const film = document.querySelector(".film");
  film.style.transform = "scale(2)";
  film.style.transformOrigin = "top left";
});
await page.waitForTimeout(12600);
const video = page.video();
await page.close();
const recorded = await video.path();
await context.close();
await browser.close();
await fs.rename(recorded, path.join(output, "writerflow-ad.webm"));
console.log(path.join(output, "writerflow-ad.webm"));

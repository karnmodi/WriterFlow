import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const output = path.join(root, "out");
const available = process.env.NEXT_PUBLIC_RELEASE_STATUS === "available";
const releaseManifest = JSON.parse(
  await readFile(new URL("../lib/release.json", import.meta.url), "utf8"),
);
const releaseBase = (
  process.env.NEXT_PUBLIC_RELEASE_ASSET_BASE_URL ??
  `https://github.com/karnmodi/WriterFlow/releases/download/v${releaseManifest.version}`
).replace(/\/$/, "");
const expectedPages = [
  "index.html",
  path.join("install", "index.html"),
  path.join("privacy", "index.html"),
  "404.html",
];

const failures = [];

for (const page of expectedPages) {
  try {
    await access(path.join(output, page));
  } catch {
    failures.push(`Missing static page: out/${page}`);
  }
}

const home = await readFile(path.join(output, "index.html"), "utf8").catch(() => "");
const install = await readFile(
  path.join(output, "install", "index.html"),
  "utf8",
).catch(() => "");
const privacy = await readFile(
  path.join(output, "privacy", "index.html"),
  "utf8",
).catch(() => "");

const requiredCopy = [
  [home, "Write better"],
  [home, "Azure OpenAI"],
  [home, "No WriterFlow account"],
  [home, "Apple silicon only"],
  [install, "Open Anyway"],
  [install, "SHA-256"],
  [install, releaseManifest.sha256],
  [install, "Downloads"],
  [privacy, "No custom WriterFlow app-facing API"],
  [privacy, "macOS Keychain"],
  [privacy, "Analyze My Writing Style"],
];

for (const [document, text] of requiredCopy) {
  if (!document.includes(text)) {
    failures.push(`Missing required launch copy: “${text}”`);
  }
}

if (available) {
  const assets = [
    ["dmg", `${releaseBase}/WriterFlow-${releaseManifest.version}.dmg`],
    ["checksum", `${releaseBase}/WriterFlow-${releaseManifest.version}.dmg.sha256`],
  ];
  for (const [asset, url] of assets) {
    if (!home.includes(`data-release-asset=\"${asset}\"`)) {
      failures.push(`Available build is missing the ${asset} download link.`);
    }
    if (!home.includes(url) || !install.includes(url)) {
      failures.push(`Available build is missing the expected ${asset} asset URL.`);
    }
  }
} else {
  if (!home.includes("Final release testing")) {
    failures.push("Candidate build is missing its release-status disclosure.");
  }
  if (home.includes("data-release-asset=\"")) {
    failures.push("Candidate build exposes a release download before the gates pass.");
  }
}

const topLevelEntries = await readdir(output).catch(() => []);
if (topLevelEntries.includes("api")) {
  failures.push("Static export unexpectedly contains an API directory.");
}

if (home.includes("NEXT_PUBLIC_") || home.includes("WriterFlow/.env")) {
  failures.push("Rendered output contains an environment-variable or local secret path.");
}

if (failures.length > 0) {
  console.error("Static export validation failed:\n");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Static export validated (${available ? "public release" : "release candidate"}): ${expectedPages.length} pages, no runtime API.`,
);

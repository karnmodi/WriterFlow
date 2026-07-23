import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";

// Replaces the old validate-export.mjs (renamed) now that next.config.ts
// dropped `output: "export"` (Stage 5.2). The three marketing pages are
// still statically prerendered at build time — just into
// `.next/server/app/<route>.html` instead of a flat `out/` directory meant
// for direct static hosting — so this validator checks the same required
// copy against the new location, plus that the standalone server the
// Dockerfile deploys actually got produced, and that /pair (the new
// server-rendered device-approval route) is NOT accidentally statically
// prerendered, which would bake a stale/empty version of it into the build.
const root = process.cwd();
const serverApp = path.join(root, ".next", "server", "app");
const standalone = path.join(root, ".next", "standalone");
const available = process.env.NEXT_PUBLIC_RELEASE_STATUS === "available";
const privateBeta = process.env.NEXT_PUBLIC_RELEASE_STATUS === "private-beta";
const releaseManifest = JSON.parse(
  await readFile(new URL("../lib/release.json", import.meta.url), "utf8"),
);
const releaseBase = (
  process.env.NEXT_PUBLIC_RELEASE_ASSET_BASE_URL ??
  `https://github.com/karnmodi/WriterFlow/releases/download/v${releaseManifest.version}`
).replace(/\/$/, "");

const failures = [];

const expectedStaticPages = ["index.html", "install.html", "membership.html", "privacy.html", "_not-found.html"];
for (const page of expectedStaticPages) {
  try {
    await access(path.join(serverApp, page));
  } catch {
    failures.push(`Missing statically prerendered page: .next/server/app/${page}`);
  }
}

try {
  await access(path.join(standalone, "server.js"));
} catch {
  failures.push("Missing .next/standalone/server.js — the Dockerfile's CMD target.");
}

// /pair must stay dynamic (ƒ in `next build`'s route table) — it will need
// a real request-time session once Entra sign-in is wired up. A .html file
// here would mean Next silently started prerendering it as static content.
try {
  await access(path.join(serverApp, "pair.html"));
  failures.push("/pair was statically prerendered — it must stay a dynamic route.");
} catch {
  // expected: no static HTML for /pair
}

const home = await readFile(path.join(serverApp, "index.html"), "utf8").catch(() => "");
const install = await readFile(path.join(serverApp, "install.html"), "utf8").catch(() => "");
const membership = await readFile(path.join(serverApp, "membership.html"), "utf8").catch(() => "");
const privacy = await readFile(path.join(serverApp, "privacy.html"), "utf8").catch(() => "");

const requiredCopy = [
  [home, "Write better"],
  [home, "WriterFlow account required"],
  [home, "Inference content is ephemeral"],
  [home, "Apple silicon only"],
  [install, "Open Anyway"],
  [install, "SHA-256"],
  [install, releaseManifest.sha256 || "The final SHA-256 will be published"],
  [install, "Sign in and approve this Mac"],
  [membership, "500 units"],
  [membership, "Pro remains in development"],
  [membership, "Not priced"],
  [privacy, "account-scoped SQLCipher database"],
  [privacy, "macOS Keychain"],
  [privacy, "Billing remains disabled"],
];

for (const [document, text] of requiredCopy) {
  if (!document.includes(text)) {
    failures.push(`Missing required launch copy: “${text}”`);
  }
}

const hasPublishedChecksum = /^[a-f0-9]{64}$/i.test(releaseManifest.sha256);
const expectsDownloadLinks = available || (privateBeta && hasPublishedChecksum);

if (expectsDownloadLinks) {
  if (!hasPublishedChecksum) {
    failures.push("Downloadable builds require a final 64-character SHA-256 in lib/release.json.");
  }
  const assets = [
    ["dmg", `${releaseBase}/WriterFlow-${releaseManifest.version}.dmg`],
    ["checksum", `${releaseBase}/WriterFlow-${releaseManifest.version}.dmg.sha256`],
  ];
  for (const [asset, url] of assets) {
    if (!home.includes(`data-release-asset=\"${asset}\"`)) {
      failures.push(`Downloadable build is missing the ${asset} download link.`);
    }
    if (!home.includes(url) || !install.includes(url)) {
      failures.push(`Downloadable build is missing the expected ${asset} asset URL.`);
    }
  }
} else {
  const expectedStatusCopy = privateBeta ? "Cloud private beta" : "Release ready";
  if (!home.includes(expectedStatusCopy)) {
    failures.push(`${privateBeta ? "Private-beta" : "Candidate"} build is missing its release-status disclosure.`);
  }
  if (home.includes("data-release-asset=\"")) {
    failures.push("Candidate build exposes a release download before the gates pass.");
  }
}

const topLevelEntries = await readdir(serverApp).catch(() => []);
if (!topLevelEntries.includes("api")) {
  failures.push("Expected the api/ route (health check) to exist in the build output.");
}

if (home.includes("NEXT_PUBLIC_") || home.includes("WriterFlow/.env")) {
  failures.push("Rendered output contains an environment-variable or local secret path.");
}

if (failures.length > 0) {
  console.error("Build validation failed:\n");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Build validated (${privateBeta ? "private beta" : available ? "public release" : "release candidate"}): ${expectedStaticPages.length} static pages, standalone server present, /pair stays dynamic.`,
);

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const manifest = JSON.parse(
  await readFile(new URL("../lib/release.json", import.meta.url), "utf8"),
);
const version = manifest.version;
const tag = `v${version}`;
const dmgFilename = `WriterFlow-${version}.dmg`;
const checksumFilename = `${dmgFilename}.sha256`;
const repositoryUrl = "https://github.com/karnmodi/WriterFlow";
const mode = process.argv[2];

function parseChecksum(text) {
  const match = text.match(/^([a-fA-F0-9]{64})\s+\*?(.+)$/m);
  if (!match) throw new Error("The checksum file is not in a recognized SHA-256 format.");

  const hash = match[1].toLowerCase();
  const filename = match[2].trim();
  if (filename !== dmgFilename) {
    throw new Error(`Checksum names ${filename}; expected ${dmgFilename}.`);
  }
  if (hash !== manifest.sha256) {
    throw new Error("Checksum file does not match lib/release.json.");
  }
  return hash;
}

async function hashLocalFile(filePath) {
  const digest = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) digest.update(chunk);
  return digest.digest("hex");
}

function remoteAssetBaseUrl() {
  const configured =
    process.env.NEXT_PUBLIC_RELEASE_ASSET_BASE_URL ??
    `${repositoryUrl}/releases/download/${tag}`;

  if (configured.startsWith("/") && !configured.startsWith("//")) {
    const siteOrigin = process.env.NEXT_PUBLIC_SITE_ORIGIN;
    if (!siteOrigin) {
      throw new Error(
        "NEXT_PUBLIC_SITE_ORIGIN is required to verify a root-relative release asset path.",
      );
    }
    return new URL(configured.replace(/\/$/, "") + "/", validateHttpsUrl(siteOrigin)).href.replace(
      /\/$/,
      "",
    );
  }

  return validateHttpsUrl(configured).href.replace(/\/$/, "");
}

function validateHttpsUrl(value) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`Invalid release URL: ${value}`);
  }

  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) {
    throw new Error("Release URLs must be credential-free HTTPS URLs without a query or fragment.");
  }
  return parsed;
}

async function fetchRequired(url) {
  const response = await fetch(url, {
    cache: "no-store",
    redirect: "follow",
    headers: { "User-Agent": "WriterFlow-release-verifier/1.0" },
  });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}.`);
  return response;
}

async function main() {
  if (mode !== "--local" && mode !== "--remote") {
    throw new Error("Use --local to verify ../build or --remote to verify published assets.");
  }

  if (mode === "--local") {
    const buildDirectory = fileURLToPath(new URL("../../build/", import.meta.url));
    const checksumText = await readFile(
      new URL(checksumFilename, `file://${buildDirectory}/`),
      "utf8",
    );
    const expectedHash = parseChecksum(checksumText);
    const actualHash = await hashLocalFile(`${buildDirectory}/${dmgFilename}`);
    if (actualHash !== expectedHash) throw new Error("Local DMG does not match its checksum.");

    console.log(`Verified local ${dmgFilename}: ${actualHash}`);
    return;
  }

  const baseUrl = remoteAssetBaseUrl();
  const checksumUrl = `${baseUrl}/${checksumFilename}`;
  const dmgUrl = `${baseUrl}/${dmgFilename}`;
  const checksumText = await (await fetchRequired(checksumUrl)).text();
  const expectedHash = parseChecksum(checksumText);
  const dmgBytes = Buffer.from(await (await fetchRequired(dmgUrl)).arrayBuffer());
  const actualHash = createHash("sha256").update(dmgBytes).digest("hex");
  if (actualHash !== expectedHash) throw new Error("Published DMG does not match its checksum.");

  console.log(`Verified published ${dmgFilename}: ${actualHash}`);
}

main().catch((error) => {
  console.error(`Release verification failed: ${error.message}`);
  process.exit(1);
});

import releaseManifest from "@/lib/release.json";

const repositoryUrl = "https://github.com/karnmodi/WriterFlow";
const version = releaseManifest.version;
const tag = `v${version}`;
const configuredAssetBaseUrl =
  process.env.NEXT_PUBLIC_RELEASE_ASSET_BASE_URL ??
  `${repositoryUrl}/releases/download/${tag}`;

function normalizeAssetBaseUrl(value: string) {
  if (value.startsWith("/") && !value.startsWith("//")) {
    return value.replace(/\/$/, "");
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error("NEXT_PUBLIC_RELEASE_ASSET_BASE_URL must be an HTTPS URL or a root-relative path.");
  }

  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) {
    throw new Error(
      "NEXT_PUBLIC_RELEASE_ASSET_BASE_URL must be a credential-free HTTPS URL without a query or fragment.",
    );
  }

  return value.replace(/\/$/, "");
}

const assetBaseUrl = normalizeAssetBaseUrl(configuredAssetBaseUrl);

export const release = {
  version,
  tag,
  status:
    process.env.NEXT_PUBLIC_RELEASE_STATUS === "available"
      ? ("available" as const)
      : ("candidate" as const),
  minimumMacOS: releaseManifest.minimumMacOS,
  architecture: releaseManifest.architecture,
  size: releaseManifest.size,
  dmgFilename: `WriterFlow-${version}.dmg`,
  checksumFilename: `WriterFlow-${version}.dmg.sha256`,
  sha256: releaseManifest.sha256,
  repositoryUrl,
  releaseUrl: `${repositoryUrl}/releases/tag/${tag}`,
  get dmgUrl() {
    return `${assetBaseUrl}/${this.dmgFilename}`;
  },
  get checksumUrl() {
    return `${assetBaseUrl}/${this.checksumFilename}`;
  },
} as const;

export const releaseIsAvailable = release.status === "available";

export const releaseStatusCopy = releaseIsAvailable
  ? "WriterFlow 1.0 is available for Apple-silicon Macs."
  : "WriterFlow 1.0 is in final release testing. Downloads open after the remaining live macOS, soak, and clean-install checks pass.";

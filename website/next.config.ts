import path from "node:path";
import type { NextConfig } from "next";

// Stage 5.2: dropped `output: "export"` — the confidential Entra client and
// /pair device-approval page (V2-ARCHITECTURE.md §14) need real server-side
// routes (cookies, a client secret) that static export cannot produce.
// `standalone` builds a minimal self-contained server for
// infra/bicep/modules/container-app-website.bicep's Docker image; the
// existing marketing pages (/, /install, /privacy) are still statically
// prerendered at build time by Next's normal per-route optimization — this
// changes the deployment/hosting model, not their runtime behavior.
const nextConfig: NextConfig = {
  output: "standalone",
  // Dropped along with `output: "export"` — trailingSlash's own redirect
  // (adding a trailing slash to every request before it reaches a route
  // handler) silently broke Entra's OAuth callback: the redirect_uri sent
  // at the authorize step (no slash, matching the registered Entra redirect
  // URI) stopped matching the URL openid-client saw at the token-exchange
  // step (slash added), which Entra correctly rejects as AADSTS500112. Not
  // worth keeping just for the marketing pages' URL style — both slash and
  // non-slash forms serve identical content either way in server mode.
  images: {
    unoptimized: true,
  },
  // This app lives inside the larger WriterFlow monorepo, which has its own
  // root package-lock.json — without pinning the root explicitly, Next
  // infers the workspace root by walking up to that outer lockfile during a
  // local build, which nests the standalone output under
  // `.next/standalone/website/server.js` instead of `.next/standalone/
  // server.js`. Dockerfile only ever copies `website/` into an isolated
  // build context (no outer lockfile visible), so an unpinned root would
  // silently produce a DIFFERENT, un-nested layout there — pinning this
  // makes local builds and the Docker build agree, rather than the mismatch
  // only surfacing as a "server.js not found" failure at deploy time.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;

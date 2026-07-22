import type { NextRequest } from "next/server";

/**
 * Public site origin for redirects and OAuth callbacks. Container Apps passes
 * requests to Next.js with an internal host (0.0.0.0:3000) — using
 * request.url's origin breaks Entra token exchange (AADSTS500112) and sends
 * browsers to an unreachable address after errors.
 */
export function siteOrigin(request?: NextRequest): string {
  const configured =
    process.env["SITE_ORIGIN"] ??
    process.env["NEXT_PUBLIC_SITE_ORIGIN"];
  if (configured) return configured.replace(/\/$/, "");

  if (request) {
    const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
    const proto = request.headers.get("x-forwarded-proto") ?? "https";
    if (host) {
      const primary = host.split(",")[0]?.trim();
      if (primary && !primary.startsWith("0.0.0.0")) {
        return `${proto}://${primary}`;
      }
    }
  }

  return "http://localhost:3000";
}

export function siteUrl(path: string, request?: NextRequest): URL {
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return new URL(normalized, siteOrigin(request));
}

/** Token-exchange URL — must use the same redirect_uri registered at authorize time. */
export function oauthCallbackUrl(request: NextRequest, registeredRedirectUri: string): URL {
  const url = new URL(registeredRedirectUri);
  url.search = new URL(request.url).search;
  return url;
}

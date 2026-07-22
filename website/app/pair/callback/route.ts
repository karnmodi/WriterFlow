import * as client from "openid-client";
import { NextResponse, type NextRequest } from "next/server";
import { getEntraConfig } from "@/lib/entra";

const COOKIE_NAME = "wf_pair_pkce";

const API_BASE_URL = process.env["WRITERFLOW_API_BASE_URL"] ?? "https://api.writerflow.app/v2";

interface PkceCookie {
  userCode: string;
  codeVerifier: string;
}

function redirectToPairPage(request: NextRequest, params: Record<string, string>): NextResponse {
  const url = new URL("/pair", request.url);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  const response = NextResponse.redirect(url);
  response.cookies.delete(COOKIE_NAME);
  return response;
}

/**
 * GET /pair/callback — Entra redirects here with ?code=...&state=...
 * (matches the Web platform redirect URI registered on the app
 * registration). Completes the flow Docs/contracts/openapi.yaml describes
 * for the website: exchange the code for an Entra ID token, trade that for
 * a WriterFlow web-session token (POST /v2/web-session/token), then bind
 * the device (POST /v2/device/approve). All server-side — never exposes the
 * ID token or web-session token to the browser.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const cookieValue = request.cookies.get(COOKIE_NAME)?.value;
  if (!cookieValue) {
    return redirectToPairPage(request, { status: "error", message: "Sign-in session expired. Try again." });
  }

  let pkce: PkceCookie;
  try {
    pkce = JSON.parse(cookieValue) as PkceCookie;
  } catch {
    return redirectToPairPage(request, { status: "error", message: "Sign-in session was invalid. Try again." });
  }

  try {
    const config = await getEntraConfig();
    const tokens = await client.authorizationCodeGrant(config, new URL(request.url), {
      pkceCodeVerifier: pkce.codeVerifier
    });
    const idToken = tokens.id_token;
    if (!idToken) {
      return redirectToPairPage(request, { status: "error", message: "Sign-in did not return an ID token." });
    }

    const webSessionResponse = await fetch(`${API_BASE_URL}/web-session/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken })
    });
    if (!webSessionResponse.ok) {
      return redirectToPairPage(request, { status: "error", message: "Could not start a WriterFlow session." });
    }
    const { accessToken } = (await webSessionResponse.json()) as { accessToken: string };

    const approveResponse = await fetch(`${API_BASE_URL}/device/approve`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({ userCode: pkce.userCode })
    });
    if (approveResponse.status === 404) {
      return redirectToPairPage(request, {
        status: "error",
        message: "That pairing code expired or was already used. Restart pairing from the Mac app."
      });
    }
    if (!approveResponse.ok) {
      return redirectToPairPage(request, { status: "error", message: "Could not approve this device." });
    }

    return redirectToPairPage(request, { status: "success" });
  } catch (error) {
    // Server-side only — openid-client's ResponseBodyError carries Entra's
    // error/error_description, never a raw token, so this is safe to log.
    console.error("pair/callback failed:", error);
    const message = error instanceof Error ? error.message : "Sign-in failed.";
    return redirectToPairPage(request, { status: "error", message });
  }
}

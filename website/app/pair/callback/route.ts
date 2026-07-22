import * as client from "openid-client";
import { NextResponse, type NextRequest } from "next/server";
import { getEntraConfig, pairRedirectUri } from "@/lib/entra";
import { oauthCallbackUrl, siteUrl } from "@/lib/site-url";
import { approveDevice, mintWebAccountToken } from "@/lib/writerflow-api";
import {
  PAIR_PKCE_COOKIE,
  setEntraLogoutHints,
  setWebAccountCookie
} from "@/lib/web-auth";
import { logoutHintFromClaims } from "@/lib/logout-hint";

const API_BASE_URL = process.env["WRITERFLOW_API_BASE_URL"] ?? "https://apiwriterflow.aviusolutions.com/v2";

function redirectToPairPage(request: NextRequest, params: Record<string, string>): NextResponse {
  const url = siteUrl("/pair", request);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  const response = NextResponse.redirect(url);
  response.cookies.delete(PAIR_PKCE_COOKIE);
  return response;
}

/**
 * GET /pair/callback — Entra pairing callback. Approves the device and also
 * establishes the durable wf_web_account cookie (ADR-0013).
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const cookieValue = request.cookies.get(PAIR_PKCE_COOKIE)?.value;
  if (!cookieValue) {
    return redirectToPairPage(request, { status: "error", message: "Sign-in session expired. Try again." });
  }

  let pkce: { userCode: string; codeVerifier: string };
  try {
    pkce = JSON.parse(cookieValue) as { userCode: string; codeVerifier: string };
  } catch {
    return redirectToPairPage(request, { status: "error", message: "Sign-in session was invalid. Try again." });
  }

  try {
    const config = await getEntraConfig();
    const tokens = await client.authorizationCodeGrant(config, oauthCallbackUrl(request, pairRedirectUri()), {
      pkceCodeVerifier: pkce.codeVerifier
    });
    const idToken = tokens.id_token;
    if (!idToken) {
      return redirectToPairPage(request, { status: "error", message: "Sign-in did not return an ID token." });
    }

    const tokenBody: { idToken: string; accessToken?: string } = { idToken };
    if (typeof tokens.access_token === "string" && tokens.access_token.length > 0) {
      tokenBody.accessToken = tokens.access_token;
    }

    const webSessionResponse = await fetch(`${API_BASE_URL}/web-session/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(tokenBody)
    });
    if (!webSessionResponse.ok) {
      return redirectToPairPage(request, { status: "error", message: "Could not start a WriterFlow session." });
    }
    const { accessToken: webSessionToken } = (await webSessionResponse.json()) as { accessToken: string };

    const approveResponse = await approveDevice(pkce.userCode, webSessionToken);
    if (approveResponse.status === 404) {
      return redirectToPairPage(request, {
        status: "error",
        message: "That pairing code expired or was already used. Restart pairing from the Mac app."
      });
    }
    if (!approveResponse.ok) {
      return redirectToPairPage(request, { status: "error", message: "Could not approve this device." });
    }

    const response = redirectToPairPage(request, { status: "success" });
    try {
      const { accessToken, expiresIn } = await mintWebAccountToken(tokenBody);
      setWebAccountCookie(response, accessToken, expiresIn);
      setEntraLogoutHints(
        response,
        idToken,
        logoutHintFromClaims(tokens.claims() as Record<string, unknown> | undefined)
      );
    } catch (accountError) {
      console.error("pair/callback: web-account cookie not set:", accountError);
    }
    return response;
  } catch (error) {
    console.error("pair/callback failed:", error);
    const message = error instanceof Error ? error.message : "Sign-in failed.";
    return redirectToPairPage(request, { status: "error", message });
  }
}

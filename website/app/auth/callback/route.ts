import * as client from "openid-client";
import { NextResponse, type NextRequest } from "next/server";
import { authRedirectUri, getEntraConfig } from "@/lib/entra";
import { oauthCallbackUrl, siteUrl } from "@/lib/site-url";
import { mintWebAccountToken } from "@/lib/writerflow-api";
import {
  AUTH_PKCE_COOKIE,
  setEntraLogoutHints,
  setWebAccountCookie
} from "@/lib/web-auth";
import { logoutHintFromClaims } from "@/lib/logout-hint";

function redirectAccount(request: NextRequest, params: Record<string, string>): NextResponse {
  const url = siteUrl("/account", request);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  const response = NextResponse.redirect(url);
  response.cookies.delete(AUTH_PKCE_COOKIE);
  return response;
}

/**
 * GET /auth/callback — completes account sign-in and sets wf_web_account cookie.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const cookieValue = request.cookies.get(AUTH_PKCE_COOKIE)?.value;
  if (!cookieValue) {
    return redirectAccount(request, { status: "error", message: "Sign-in session expired. Try again." });
  }

  let pkce: { returnTo: string; codeVerifier: string };
  try {
    pkce = JSON.parse(cookieValue) as { returnTo: string; codeVerifier: string };
  } catch {
    return redirectAccount(request, { status: "error", message: "Sign-in session was invalid. Try again." });
  }

  try {
    const config = await getEntraConfig();
    const tokens = await client.authorizationCodeGrant(config, oauthCallbackUrl(request, authRedirectUri()), {
      pkceCodeVerifier: pkce.codeVerifier
    });
    const idToken = tokens.id_token;
    if (!idToken) {
      return redirectAccount(request, { status: "error", message: "Sign-in did not return an ID token." });
    }

    const webAccountBody: { idToken: string; accessToken?: string } = { idToken };
    if (typeof tokens.access_token === "string" && tokens.access_token.length > 0) {
      webAccountBody.accessToken = tokens.access_token;
    }

    const { accessToken, expiresIn } = await mintWebAccountToken(webAccountBody);
    const destination = pkce.returnTo.startsWith("/") ? pkce.returnTo : "/account";
    const response = NextResponse.redirect(siteUrl(destination, request));
    response.cookies.delete(AUTH_PKCE_COOKIE);
    setWebAccountCookie(response, accessToken, expiresIn);
    setEntraLogoutHints(response, idToken, logoutHintFromClaims(tokens.claims() as Record<string, unknown> | undefined));
    return response;
  } catch (error) {
    console.error("auth/callback failed:", error);
    const message = error instanceof Error ? error.message : "Sign-in failed.";
    return redirectAccount(request, { status: "error", message });
  }
}

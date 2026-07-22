import * as client from "openid-client";
import { NextResponse, type NextRequest } from "next/server";
import { authRedirectUri, getEntraConfig } from "@/lib/entra";

const AUTH_PKCE_COOKIE = "wf_auth_pkce";

/**
 * GET /auth/start — general account sign-in (ADR-0013). Redirects to Entra;
 * callback establishes the durable wf_web_account cookie.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const returnTo = request.nextUrl.searchParams.get("returnTo") ?? "/account";
  const config = await getEntraConfig();
  const codeVerifier = client.randomPKCECodeVerifier();
  const codeChallenge = await client.calculatePKCECodeChallenge(codeVerifier);

  const authorizationUrl = client.buildAuthorizationUrl(config, {
    redirect_uri: authRedirectUri(),
    scope: "openid profile email",
    // Force email entry / fresh auth — without this, Entra may skip straight to
    // "Enter code" for a remembered account and OTP never actually sends.
    prompt: "login",
    code_challenge: codeChallenge,
    code_challenge_method: "S256"
  });

  const response = NextResponse.redirect(authorizationUrl);
  response.cookies.set(AUTH_PKCE_COOKIE, JSON.stringify({ returnTo, codeVerifier }), {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge: 600,
    path: "/auth"
  });
  return response;
}

export { AUTH_PKCE_COOKIE };

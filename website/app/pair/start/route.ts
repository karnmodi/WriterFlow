import * as client from "openid-client";
import { NextResponse, type NextRequest } from "next/server";
import { getEntraConfig, pairRedirectUri } from "@/lib/entra";

const COOKIE_NAME = "wf_pair_pkce";

/**
 * GET /pair/start?user_code=... — kicks off the real Entra sign-in
 * (V2-ARCHITECTURE.md §5.1 step 3). Stores the PKCE verifier and the
 * device's user_code together in one short-lived httpOnly cookie so
 * /pair/callback can recover both after the redirect round trip; never
 * exposed to client-side JS, never logged.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const userCode = request.nextUrl.searchParams.get("user_code");
  if (!userCode) {
    return NextResponse.json({ error: "Missing user_code" }, { status: 400 });
  }

  const config = await getEntraConfig();
  const codeVerifier = client.randomPKCECodeVerifier();
  const codeChallenge = await client.calculatePKCECodeChallenge(codeVerifier);

  const authorizationUrl = client.buildAuthorizationUrl(config, {
    redirect_uri: pairRedirectUri(),
    scope: "openid",
    code_challenge: codeChallenge,
    code_challenge_method: "S256"
  });

  const response = NextResponse.redirect(authorizationUrl);
  response.cookies.set(COOKIE_NAME, JSON.stringify({ userCode, codeVerifier }), {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge: 600,
    path: "/pair"
  });
  return response;
}

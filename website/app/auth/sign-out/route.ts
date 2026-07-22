import { NextResponse, type NextRequest } from "next/server";
import { buildEntraLogoutUrl, canFederatedLogout } from "@/lib/entra";
import { siteUrl } from "@/lib/site-url";
import {
  clearWebAuthCookies,
  ENTRA_ID_TOKEN_HINT_COOKIE,
  ENTRA_LOGOUT_HINT_COOKIE
} from "@/lib/web-auth";

/**
 * GET /auth/sign-out — clears WriterFlow cookies, then Entra end_session when
 * we have id_token_hint and/or logout_hint. Without a hint, CIAM shows an
 * empty "Pick an account" screen — so fall back to local signed-out page.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const idTokenHint = request.cookies.get(ENTRA_ID_TOKEN_HINT_COOKIE)?.value;
  const logoutHint = request.cookies.get(ENTRA_LOGOUT_HINT_COOKIE)?.value;
  const params = {
    idTokenHint: idTokenHint || undefined,
    logoutHint: logoutHint || undefined
  };

  if (canFederatedLogout(params)) {
    const response = NextResponse.redirect(await buildEntraLogoutUrl(params));
    clearWebAuthCookies(response);
    return response;
  }

  const response = NextResponse.redirect(siteUrl("/account?signedOut=1", request));
  clearWebAuthCookies(response);
  return response;
}

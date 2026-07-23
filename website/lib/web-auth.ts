import type { ResponseCookie } from "next/dist/compiled/@edge-runtime/cookies";
import type { NextResponse } from "next/server";

export const WEB_ACCOUNT_COOKIE = "wf_web_account";
/** Full ID token for end_session id_token_hint — only stored when it fits in a cookie. */
export const ENTRA_ID_TOKEN_HINT_COOKIE = "wf_entra_id_token_hint";
/** Compact login identifier (email) for Entra logout_hint — always preferred for CIAM. */
export const ENTRA_LOGOUT_HINT_COOKIE = "wf_entra_logout_hint";
export const PAIR_PKCE_COOKIE = "wf_pair_pkce";
export const AUTH_PKCE_COOKIE = "wf_auth_pkce";

/** Browsers reject Set-Cookie values much past ~4KB; ID tokens often exceed that. */
const MAX_ID_TOKEN_COOKIE_CHARS = 3500;

function cookieBase(maxAge: number): Omit<ResponseCookie, "name" | "value"> {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge,
    path: "/"
  };
}

export function setWebAccountCookie(response: NextResponse, token: string, expiresIn: number): void {
  response.cookies.set(WEB_ACCOUNT_COOKIE, token, cookieBase(expiresIn));
}

/**
 * Stores Entra logout hints after sign-in. Prefer a small email logout_hint;
 * only persist id_token_hint when the JWT fits in a cookie (otherwise CIAM
 * end_session shows an empty "Pick an account" screen).
 */
export function setEntraLogoutHints(
  response: NextResponse,
  idToken: string,
  logoutHint?: string | null
): void {
  const hint = logoutHint?.trim();
  if (hint) {
    response.cookies.set(ENTRA_LOGOUT_HINT_COOKIE, hint, cookieBase(60 * 60 * 24 * 7));
  }
  if (idToken.length <= MAX_ID_TOKEN_COOKIE_CHARS) {
    response.cookies.set(ENTRA_ID_TOKEN_HINT_COOKIE, idToken, cookieBase(60 * 60));
  }
}

/** @deprecated Prefer setEntraLogoutHints — kept for call-site clarity aliases. */
export function setEntraIdTokenHintCookie(response: NextResponse, idToken: string): void {
  setEntraLogoutHints(response, idToken, null);
}

export function clearWebAuthCookies(response: NextResponse): void {
  response.cookies.delete(WEB_ACCOUNT_COOKIE);
  response.cookies.delete(ENTRA_ID_TOKEN_HINT_COOKIE);
  response.cookies.delete(ENTRA_LOGOUT_HINT_COOKIE);
  response.cookies.delete(PAIR_PKCE_COOKIE);
  response.cookies.delete(AUTH_PKCE_COOKIE);
}

export function readWebAccountToken(cookieValue: string | undefined): string | null {
  if (!cookieValue?.trim()) return null;
  return cookieValue;
}

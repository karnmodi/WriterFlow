import { NextResponse, type NextRequest } from "next/server";
import { siteUrl } from "@/lib/site-url";
import { approveDevice, bridgeWebSession } from "@/lib/writerflow-api";
import { PAIR_PKCE_COOKIE, readWebAccountToken, WEB_ACCOUNT_COOKIE } from "@/lib/web-auth";

function redirectPair(request: NextRequest, params: Record<string, string>): NextResponse {
  const url = siteUrl("/pair", request);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return NextResponse.redirect(url);
}

/**
 * GET /pair/approve?user_code=... — approve a device using an existing web-account
 * session (skip Entra when already signed in).
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const userCode = request.nextUrl.searchParams.get("user_code");
  if (!userCode) {
    return redirectPair(request, { status: "error", message: "Missing pairing code." });
  }

  const token = readWebAccountToken(request.cookies.get(WEB_ACCOUNT_COOKIE)?.value);
  if (!token) {
    return redirectPair(request, {
      status: "error",
      message: "Sign in to approve this device.",
      user_code: userCode
    });
  }

  try {
    const webSessionToken = await bridgeWebSession(token);
    const approveResponse = await approveDevice(userCode, webSessionToken);
    if (approveResponse.status === 404) {
      return redirectPair(request, {
        status: "error",
        message: "That pairing code expired or was already used. Restart pairing from the Mac app.",
        user_code: userCode
      });
    }
    if (!approveResponse.ok) {
      return redirectPair(request, {
        status: "error",
        message: "Could not approve this device.",
        user_code: userCode
      });
    }
    const response = redirectPair(request, { status: "success", user_code: userCode });
    response.cookies.delete(PAIR_PKCE_COOKIE);
    return response;
  } catch (error) {
    console.error("pair/approve failed:", error);
    return redirectPair(request, {
      status: "error",
      message: "Could not approve this device with your current session.",
      user_code: userCode
    });
  }
}

import type { Metadata } from "next";
import { cookies } from "next/headers";

import {
  AuthHint,
  AuthPanel,
  AuthPrimaryLink
} from "@/components/AuthPanel";
import { fetchWebMe } from "@/lib/writerflow-api";
import { readWebAccountToken, WEB_ACCOUNT_COOKIE } from "@/lib/web-auth";

export const metadata: Metadata = {
  title: "Pair a device",
  description: "Approve a WriterFlow Mac app device-pairing request.",
  robots: { index: false, follow: false }
};

export const dynamic = "force-dynamic";

interface PairPageProps {
  searchParams: Promise<{ user_code?: string; status?: string; message?: string }>;
}

/**
 * V2-ARCHITECTURE.md §5.1 step 3 / ADR-0013. When the visitor already has a
 * web-account cookie, /pair/approve skips Entra; otherwise /pair/start runs
 * Microsoft sign-in and /pair/callback completes approval + sets the cookie.
 */
export default async function PairPage({ searchParams }: PairPageProps) {
  const { user_code: userCode, status, message } = await searchParams;
  const cookieStore = await cookies();
  const webToken = readWebAccountToken(cookieStore.get(WEB_ACCOUNT_COOKIE)?.value);
  const webSession = webToken ? await fetchWebMe(webToken).catch(() => null) : null;

  if (status === "success") {
    return (
      <AuthPanel
        eyebrow="Device pairing"
        title="Device approved"
        description="WriterFlow on your Mac should finish signing in within a few seconds. You can close this tab."
      />
    );
  }

  if (status === "error") {
    return (
      <AuthPanel
        eyebrow="Device pairing"
        title="Couldn’t approve this device"
        description={message ?? "Something went wrong during sign-in."}
      >
        {userCode ? (
          webSession ? (
            <AuthPrimaryLink href={`/pair/approve?user_code=${encodeURIComponent(userCode)}`}>
              Try again as {webSession.displayName ?? webSession.email ?? "signed-in user"}
            </AuthPrimaryLink>
          ) : (
            <>
              <AuthPrimaryLink href={`/pair/start?user_code=${encodeURIComponent(userCode)}`}>
                Continue to sign in
              </AuthPrimaryLink>
              <AuthHint>
                Use the same sign-in method as before (Google vs email code). Entra won’t send a
                one-time code for an email that already has a Google account.
              </AuthHint>
            </>
          )
        ) : null}
      </AuthPanel>
    );
  }

  return (
    <AuthPanel
      eyebrow="Device pairing"
      title="Approve this Mac"
      description="Confirm it’s you, then WriterFlow will finish signing in on the Mac. We never see your password — sign-in happens with Microsoft."
    >
      {userCode ? (
        <p className="rounded-2xl border border-black/8 bg-white/70 px-4 py-3 font-mono text-sm tracking-wide text-ink">
          Code from your Mac: <strong className="font-semibold">{userCode}</strong>
        </p>
      ) : (
        <AuthHint>
          No code was included in this link — open this page from the WriterFlow app instead.
        </AuthHint>
      )}

      {userCode ? (
        webSession ? (
          <>
            <p className="text-sm leading-6 text-black/60">
              Signed in as{" "}
              <strong className="font-semibold text-ink">
                {webSession.displayName ?? webSession.email ?? "your account"}
              </strong>
              . Approve this Mac without signing in again.
            </p>
            <AuthPrimaryLink href={`/pair/approve?user_code=${encodeURIComponent(userCode)}`}>
              Approve this device
            </AuthPrimaryLink>
            <p className="text-center text-xs text-black/45">
              Not you?{" "}
              <a className="underline decoration-black/25 underline-offset-2" href="/auth/sign-out">
                Sign out
              </a>{" "}
              and use a different account.
            </p>
          </>
        ) : (
          <>
            <AuthPrimaryLink href={`/pair/start?user_code=${encodeURIComponent(userCode)}`}>
              Continue to sign in
            </AuthPrimaryLink>
            <AuthHint>
              On Microsoft’s next screen, pick the method you already use. Prefer{" "}
              <strong>Google</strong> if that email was created with Google — email one-time codes
              are only sent for email sign-in, and Entra blocks a second signup for the same
              address.
            </AuthHint>
          </>
        )
      ) : null}
    </AuthPanel>
  );
}

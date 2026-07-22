import type { Metadata } from "next";
import { cookies } from "next/headers";
import Link from "next/link";

import {
  AuthHint,
  AuthPanel,
  AuthPrimaryLink,
  AuthSecondaryLink
} from "@/components/AuthPanel";
import { fetchWebMe } from "@/lib/writerflow-api";
import { readWebAccountToken, WEB_ACCOUNT_COOKIE } from "@/lib/web-auth";

export const metadata: Metadata = {
  title: "Account",
  description: "Your WriterFlow account — membership and device pairing.",
  robots: { index: false, follow: false }
};

export const dynamic = "force-dynamic";

interface AccountPageProps {
  searchParams: Promise<{ status?: string; message?: string; signedOut?: string }>;
}

function displayTitle(snapshot: { displayName: string | null; email: string | null }): string {
  if (snapshot.displayName?.trim()) return snapshot.displayName.trim();
  if (snapshot.email?.trim()) return snapshot.email.trim();
  return "Signed in";
}

export default async function AccountPage({ searchParams }: AccountPageProps) {
  const params = await searchParams;
  const cookieStore = await cookies();
  const token = readWebAccountToken(cookieStore.get(WEB_ACCOUNT_COOKIE)?.value);
  const snapshot = token ? await fetchWebMe(token).catch(() => null) : null;

  if (params.signedOut === "1") {
    return (
      <AuthPanel
        eyebrow="Account"
        title="Signed out"
        description="You’ve been signed out of WriterFlow and Microsoft on this browser."
      >
        <AuthPrimaryLink href="/auth/start">Sign in again</AuthPrimaryLink>
      </AuthPanel>
    );
  }

  if (params.status === "error") {
    return (
      <AuthPanel
        eyebrow="Account"
        title="Sign-in failed"
        description={params.message ?? "Something went wrong during sign-in."}
      >
        <AuthPrimaryLink href="/auth/start">Try again</AuthPrimaryLink>
      </AuthPanel>
    );
  }

  if (!snapshot) {
    return (
      <AuthPanel
        eyebrow="Account"
        title="Sign in to WriterFlow"
        description="Manage membership and approve Mac devices. Your Mac app stays signed in on its own — signing in here doesn’t change the app until you pair a device."
      >
        <AuthPrimaryLink href="/auth/start">Continue to sign in</AuthPrimaryLink>
        <AuthHint>
          On the next screen, use the same method you used before. If you signed in with{" "}
          <strong>Google</strong>, choose Google — Entra won’t email a one-time code for an address
          that already has a Google account (“An account with that email address already exists”).
          Email codes are only sent when you sign in with email on an address that isn’t already
          registered another way.
        </AuthHint>
      </AuthPanel>
    );
  }

  return (
    <AuthPanel
      eyebrow="Signed in"
      title={displayTitle(snapshot)}
      description={
        snapshot.email ? (
          <span>{snapshot.email}</span>
        ) : (
          "Your WriterFlow web account is ready."
        )
      }
    >
      <dl className="grid gap-4 rounded-2xl border border-black/8 bg-white/70 p-5">
        <div className="flex justify-between gap-4">
          <dt className="text-sm text-black/55">Plan</dt>
          <dd className="text-sm font-medium capitalize">{snapshot.entitlement.plan}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-sm text-black/55">Monthly units</dt>
          <dd className="text-sm font-medium">
            {snapshot.entitlement.monthlyUnitsUsed}/{snapshot.entitlement.monthlyUnitsIncluded}
          </dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-sm text-black/55">Personalization sync</dt>
          <dd className="text-sm font-medium">
            {snapshot.privacy.personalizationSyncEnabled ? "On" : "Off"}
          </dd>
        </div>
      </dl>

      <p className="text-sm leading-7 text-black/55">
        To approve a Mac, open the pairing link from the WriterFlow app or visit{" "}
        <Link className="font-medium text-ink underline decoration-black/25 underline-offset-2" href="/pair">
          /pair
        </Link>
        . Membership billing will live here in a later release.
      </p>

      <AuthSecondaryLink href="/auth/sign-out">Sign out</AuthSecondaryLink>
    </AuthPanel>
  );
}

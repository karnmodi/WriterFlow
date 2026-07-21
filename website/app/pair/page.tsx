import type { Metadata } from "next";

import { ShieldIcon } from "@/components/Icons";

export const metadata: Metadata = {
  title: "Pair a device",
  description: "Approve a WriterFlow Mac app device-pairing request.",
  robots: { index: false, follow: false },
};

interface PairPageProps {
  searchParams: Promise<{ user_code?: string }>;
}

/**
 * V2-ARCHITECTURE.md §5.1 step 3 / Docs/contracts/openapi.yaml POST
 * /device/approve. The Mac app opens `writerflow.app/pair?user_code=...`
 * (or a person types the code here manually) expecting this page to run
 * Entra sign-in, then call POST /v2/device/approve with a WriterFlow
 * web-session token (POST /v2/web-session/token) under its own session.
 *
 * Stub only for now — this route exists (Container Apps deployment target,
 * URL shape the Mac client already generates) but does not yet sign anyone
 * in. Entra sign-in wiring (a real OIDC library, session cookies, the
 * ENTRA_* config this needs) is a separate, deliberately not-yet-started
 * increment — building a page that *looks* functional before there's a
 * real Entra tenant to sign in against would be actively misleading.
 */
export default async function PairPage({ searchParams }: PairPageProps) {
  const { user_code: userCode } = await searchParams;

  return (
    <main id="main-content">
      <section className="bg-paper py-16 sm:py-24">
        <div className="site-shell max-w-xl">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-black/10 bg-black/5 text-blue">
            <ShieldIcon className="size-6" />
          </span>
          <h1 className="mt-6 font-display text-4xl tracking-tight">Device pairing isn&apos;t live yet</h1>
          <p className="mt-4 text-lg leading-8 text-black/70">
            This page will let you sign in and approve a WriterFlow Mac app on this account.
            That flow isn&apos;t wired up yet — check back once WriterFlow accounts are
            available.
          </p>
          {userCode ? (
            <p className="mt-6 rounded-xl border border-black/10 bg-black/5 px-4 py-3 font-mono text-sm">
              Code from your Mac: <strong>{userCode}</strong>
            </p>
          ) : null}
        </div>
      </section>
    </main>
  );
}

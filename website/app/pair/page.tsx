import type { Metadata } from "next";

import { CheckIcon, ShieldIcon } from "@/components/Icons";

export const metadata: Metadata = {
  title: "Pair a device",
  description: "Approve a WriterFlow Mac app device-pairing request.",
  robots: { index: false, follow: false },
};

interface PairPageProps {
  searchParams: Promise<{ user_code?: string; status?: string; message?: string }>;
}

/**
 * V2-ARCHITECTURE.md §5.1 step 3 / Docs/contracts/openapi.yaml POST
 * /device/approve. The Mac app opens `writerflow.app/pair?user_code=...`
 * (or a person types the code here manually). Signing in redirects to
 * /pair/start, which sends the browser to Entra; /pair/callback completes
 * the exchange and redirects back here with ?status=success|error.
 */
export default async function PairPage({ searchParams }: PairPageProps) {
  const { user_code: userCode, status, message } = await searchParams;

  if (status === "success") {
    return (
      <main id="main-content">
        <section className="bg-paper py-16 sm:py-24">
          <div className="site-shell max-w-xl">
            <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-black/10 bg-black/5 text-blue">
              <CheckIcon className="size-6" />
            </span>
            <h1 className="mt-6 font-display text-4xl tracking-tight">Device approved</h1>
            <p className="mt-4 text-lg leading-8 text-black/70">
              WriterFlow on your Mac should finish signing in within a few seconds. You can close
              this tab.
            </p>
          </div>
        </section>
      </main>
    );
  }

  if (status === "error") {
    return (
      <main id="main-content">
        <section className="bg-paper py-16 sm:py-24">
          <div className="site-shell max-w-xl">
            <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-black/10 bg-black/5 text-blue">
              <ShieldIcon className="size-6" />
            </span>
            <h1 className="mt-6 font-display text-4xl tracking-tight">Couldn&apos;t approve this device</h1>
            <p className="mt-4 text-lg leading-8 text-black/70">
              {message ?? "Something went wrong during sign-in."}
            </p>
            {userCode ? (
              <a
                href={`/pair/start?user_code=${encodeURIComponent(userCode)}`}
                className="mt-6 inline-flex items-center justify-center rounded-full bg-blue px-6 py-3 text-sm font-medium text-white"
              >
                Try again
              </a>
            ) : null}
          </div>
        </section>
      </main>
    );
  }

  return (
    <main id="main-content">
      <section className="bg-paper py-16 sm:py-24">
        <div className="site-shell max-w-xl">
          <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-black/10 bg-black/5 text-blue">
            <ShieldIcon className="size-6" />
          </span>
          <h1 className="mt-6 font-display text-4xl tracking-tight">Approve this device</h1>
          <p className="mt-4 text-lg leading-8 text-black/70">
            Sign in to approve the WriterFlow Mac app that sent you here. WriterFlow never sees
            your password — sign-in happens with Microsoft.
          </p>
          {userCode ? (
            <p className="mt-6 rounded-xl border border-black/10 bg-black/5 px-4 py-3 font-mono text-sm">
              Code from your Mac: <strong>{userCode}</strong>
            </p>
          ) : (
            <p className="mt-6 text-sm text-black/60">
              No code was included in this link — open this page from the WriterFlow app instead.
            </p>
          )}
          {userCode ? (
            <a
              href={`/pair/start?user_code=${encodeURIComponent(userCode)}`}
              className="mt-6 inline-flex items-center justify-center rounded-full bg-blue px-6 py-3 text-sm font-medium text-white"
            >
              Sign in with Microsoft
            </a>
          ) : null}
        </div>
      </section>
    </main>
  );
}

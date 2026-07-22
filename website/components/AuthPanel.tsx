import type { ReactNode } from "react";

import { Wordmark } from "@/components/BrandMark";

type AuthPanelProps = {
  title: string;
  description: ReactNode;
  children?: ReactNode;
  eyebrow?: string;
};

/**
 * Shared chrome for /account and /pair — brand-first, one job per screen.
 * Entra's hosted OTP / IdP pages are separate; polish those via company branding
 * assets under `website/public/brand/`.
 */
export function AuthPanel({ title, description, children, eyebrow }: AuthPanelProps) {
  return (
    <main id="main-content">
      <section className="auth-panel relative overflow-hidden py-14 sm:py-20">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_20%_0%,rgba(20,40,255,0.08),transparent_55%),radial-gradient(ellipse_at_90%_30%,rgba(17,19,26,0.06),transparent_45%)]"
        />
        <div className="site-shell relative flex justify-center">
          <div className="w-full max-w-md">
            <Wordmark />
            {eyebrow ? (
              <p className="mt-8 text-xs font-semibold uppercase tracking-[0.14em] text-black/45">
                {eyebrow}
              </p>
            ) : null}
            <h1
              className={`font-display text-[2.15rem] leading-tight tracking-tight text-ink sm:text-4xl ${
                eyebrow ? "mt-2" : "mt-8"
              }`}
            >
              {title}
            </h1>
            <div className="mt-4 text-[1.05rem] leading-8 text-black/65">{description}</div>
            {children ? <div className="mt-8 space-y-5">{children}</div> : null}
          </div>
        </div>
      </section>
    </main>
  );
}

export function AuthPrimaryLink({
  href,
  children
}: {
  href: string;
  children: ReactNode;
}) {
  return (
    <a
      href={href}
      className="inline-flex w-full items-center justify-center rounded-full bg-blue px-6 py-3.5 text-sm font-semibold text-white transition hover:bg-blue-deep"
    >
      {children}
    </a>
  );
}

export function AuthSecondaryLink({
  href,
  children
}: {
  href: string;
  children: ReactNode;
}) {
  return (
    <a
      href={href}
      className="inline-flex w-full items-center justify-center rounded-full border border-black/12 bg-white/50 px-6 py-3.5 text-sm font-semibold text-ink transition hover:border-black/25 hover:bg-white"
    >
      {children}
    </a>
  );
}

export function AuthHint({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-black/8 bg-white/60 px-4 py-3.5 text-sm leading-6 text-black/60">
      {children}
    </div>
  );
}

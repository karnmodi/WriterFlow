import Link from "next/link";

import { ChevronRightIcon } from "@/components/Icons";

export default function NotFound() {
  return (
    <main className="flex min-h-[70svh] items-center bg-paper" id="main-content">
      <div className="site-shell py-20 text-center">
        <p className="section-kicker text-blue">404 / Lost the thread</p>
        <h1 className="mt-5 font-display text-[clamp(4rem,10vw,8rem)] leading-none tracking-[-0.06em] text-ink">
          This page drifted away.
        </h1>
        <p className="mx-auto mt-6 max-w-md text-base leading-7 text-ink/58">
          The link may have moved, but your way back to WriterFlow is still right here.
        </p>
        <Link className="button-primary mt-8" href="/">
          Return home
          <ChevronRightIcon className="size-5" />
        </Link>
      </div>
    </main>
  );
}

import Link from "next/link";

import { Wordmark } from "@/components/BrandMark";
import { ArrowDownIcon } from "@/components/Icons";
import { release, releaseIsAvailable, releaseIsPrivateBeta } from "@/lib/release";

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="site-shell flex h-[76px] items-center justify-between gap-6">
        <Link
          aria-label="WriterFlow home"
          className="focus-ring inline-flex min-h-11 items-center rounded-xl"
          href="/"
        >
          <Wordmark />
        </Link>

        <nav aria-label="Primary navigation" className="hidden items-center gap-7 md:flex">
          <Link className="nav-link" href="/#how-it-works">
            How it works
          </Link>
          <Link className="nav-link" href="/privacy/">
            Privacy
          </Link>
          <Link className="nav-link" href="/install/">
            Install
          </Link>
          <Link className="nav-link" href="/membership">
            Membership
          </Link>
          <Link className="nav-link" href="/account">
            Account
          </Link>
        </nav>

        {releaseIsAvailable ? (
          <a
            className="header-download"
            data-release-asset="dmg"
            download={release.dmgFilename}
            href={release.dmgUrl}
          >
            <span className="hidden sm:inline">Download 1.0</span>
            <span className="sm:hidden">Download</span>
            <ArrowDownIcon className="size-[18px]" />
          </a>
        ) : releaseIsPrivateBeta ? (
          <Link className="header-download" href="/account">
            Private beta
            <span aria-hidden="true" className="status-pulse" />
          </Link>
        ) : (
          <Link className="header-download" href="/#download">
            Release status
            <span aria-hidden="true" className="status-pulse" />
          </Link>
        )}
      </div>

      <nav
        aria-label="Mobile navigation"
        className="site-shell flex h-11 items-center justify-end gap-6 border-t border-ink/8 md:hidden"
      >
        <Link className="nav-link" href="/#how-it-works">
          How it works
        </Link>
        <Link className="nav-link" href="/privacy/">
          Privacy
        </Link>
        <Link className="nav-link" href="/install/">
          Install
        </Link>
        <Link className="nav-link" href="/membership">
          Membership
        </Link>
        <Link className="nav-link" href="/account">
          Account
        </Link>
      </nav>
    </header>
  );
}

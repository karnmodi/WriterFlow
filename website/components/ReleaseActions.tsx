import Link from "next/link";

import { ArrowDownIcon, ChevronRightIcon } from "@/components/Icons";
import { release, releaseIsAvailable, releaseIsPrivateBeta } from "@/lib/release";

type ReleaseActionsProps = {
  className?: string;
  dark?: boolean;
};

export function ReleaseActions({ className = "", dark = false }: ReleaseActionsProps) {
  const secondaryClass = dark
    ? "border-white/20 text-paper hover:border-white/45 hover:bg-white/8"
    : "border-ink/15 text-ink hover:border-ink/35 hover:bg-white/65";

  if (releaseIsPrivateBeta) {
    return (
      <div className={`flex flex-col gap-3 sm:flex-row ${className}`}>
        <Link className="button-primary" href="/account">
          Sign in for private beta
          <ChevronRightIcon className="size-5" />
        </Link>
        <Link className={`button-secondary ${secondaryClass}`} href="/install/">
          Read the install guide
          <ChevronRightIcon className="size-5" />
        </Link>
      </div>
    );
  }

  if (!releaseIsAvailable) {
    return (
      <div className={`flex flex-col gap-3 sm:flex-row ${className}`}>
        <span
          aria-disabled="true"
          className="button-primary cursor-not-allowed opacity-60"
          title="Downloads open when the final DMG and checksum are published"
        >
          Release ready
          <span aria-hidden="true" className="status-pulse" />
        </span>
        <Link className={`button-secondary ${secondaryClass}`} href="/install/">
          Read the install guide
          <ChevronRightIcon className="size-5" />
        </Link>
      </div>
    );
  }

  return (
    <div className={`flex flex-col gap-3 sm:flex-row ${className}`}>
      <a
        className="button-primary"
        data-release-asset="dmg"
        download={release.dmgFilename}
        href={release.dmgUrl}
      >
        Download for Mac
        <ArrowDownIcon className="size-5" />
      </a>
      <a
        className={`button-secondary ${secondaryClass}`}
        data-release-asset="checksum"
        download={release.checksumFilename}
        href={release.checksumUrl}
      >
        Get SHA-256
        <ArrowDownIcon className="size-5" />
      </a>
    </div>
  );
}

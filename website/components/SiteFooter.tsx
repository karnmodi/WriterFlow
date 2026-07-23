import Link from "next/link";

import { Wordmark } from "@/components/BrandMark";
import { ArrowUpRightIcon } from "@/components/Icons";
import { release, releaseHasDownload } from "@/lib/release";

export function SiteFooter() {
  return (
    <footer className="bg-ink text-paper">
      <div className="site-shell py-10 sm:py-12">
        <div className="flex flex-col gap-10 border-b border-white/12 pb-10 md:flex-row md:items-start md:justify-between">
          <div className="max-w-sm">
            <Link
              aria-label="WriterFlow home"
              className="focus-ring inline-flex min-h-11 items-center rounded-xl"
              href="/"
            >
              <Wordmark inverse />
            </Link>
            <p className="mt-4 text-sm leading-6 text-white/68">
              A native macOS writing assistant for clearer drafts and contextual replies,
              right where you type.
            </p>
          </div>

          <nav aria-label="Footer navigation" className="grid grid-cols-2 gap-x-12 gap-y-3 text-sm sm:grid-cols-3">
            <Link className="footer-link" href="/#how-it-works">
              How it works
            </Link>
            <Link className="footer-link" href="/privacy/">
              Privacy
            </Link>
            <Link className="footer-link" href="/install/">
              Install guide
            </Link>
            <Link className="footer-link" href="/membership">
              Membership
            </Link>
            <a className="footer-link inline-flex items-center gap-1" href={release.repositoryUrl}>
              GitHub
              <ArrowUpRightIcon className="size-4" />
            </a>
            {releaseHasDownload ? (
              <a className="footer-link inline-flex items-center gap-1" href={release.releaseUrl}>
                Release
                <ArrowUpRightIcon className="size-4" />
              </a>
            ) : (
              <Link className="footer-link" href="/#download">
                Release status
              </Link>
            )}
          </nav>
        </div>

        <div className="flex flex-col gap-2 pt-6 text-xs text-white/65 sm:flex-row sm:items-center sm:justify-between">
          <p>© 2026 WriterFlow. Version {release.version} · Private beta.</p>
          <p>Free includes 500 units · Pro is in development.</p>
        </div>
      </div>
    </footer>
  );
}

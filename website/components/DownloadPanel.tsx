import Link from "next/link";

import { ReleaseActions } from "@/components/ReleaseActions";
import { ArrowUpRightIcon, ShieldIcon } from "@/components/Icons";
import {
  release,
  releaseHasDownload,
  releaseIsAvailable,
  releaseIsPrivateBeta,
  releaseStatusCopy,
} from "@/lib/release";

export function DownloadPanel() {
  return (
    <section className="download-section scroll-mt-24" id="download">
      <div className="download-orbit" />
      <div className="site-shell relative py-20 sm:py-28">
        <div className="grid items-start gap-12 lg:grid-cols-[0.86fr_1.14fr] lg:gap-20">
          <div className="lg:sticky lg:top-28">
            <p className="section-kicker text-cobalt-light">WriterFlow {release.version}</p>
            <h2 className="mt-5 max-w-xl font-display text-[clamp(3.1rem,7vw,6.7rem)] leading-[0.88] tracking-[-0.06em] text-paper">
              Ready when your words are.
            </h2>
            <p className="mt-7 max-w-lg text-base leading-7 text-white/60 sm:text-lg">
              WriterFlow 2.0 connects the Mac app to your account and authenticated cloud
              service. Sign in, pair your Mac, and review every result before replacement.
            </p>
          </div>

          <div className="release-ticket">
            <div className="flex flex-col gap-6 border-b border-white/12 pb-7 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-xs font-semibold tracking-[0.14em] text-white/68 uppercase">
                  {releaseIsPrivateBeta
                    ? "Private beta"
                    : releaseIsAvailable
                      ? "Public release"
                      : "Release candidate"}
                </p>
                <p className="mt-2 text-2xl font-semibold tracking-[-0.03em] text-paper">
                  Version {release.version}
                </p>
              </div>
              <span
                className={`release-status ${
                  releaseHasDownload ? "release-status-live" : "release-status-candidate"
                }`}
              >
                <span aria-hidden="true" className="status-pulse" />
                {releaseHasDownload
                  ? releaseIsPrivateBeta
                    ? "Download open"
                    : "Available now"
                  : releaseIsPrivateBeta
                    ? "Limited access"
                    : "Ready to publish"}
              </span>
            </div>

            <p className="mt-7 text-sm leading-6 text-white/62">{releaseStatusCopy}</p>

            <dl className="release-manifest">
              <div>
                <dt>System</dt>
                <dd>{release.minimumMacOS}</dd>
              </div>
              <div>
                <dt>Hardware</dt>
                <dd>{release.architecture}</dd>
              </div>
              <div>
                <dt>Package</dt>
                <dd>{release.dmgFilename}</dd>
              </div>
              <div>
                <dt>Integrity</dt>
                <dd>Separate SHA-256 file</dd>
              </div>
            </dl>

            <ReleaseActions className="mt-8" dark />

            <div className="mt-7 flex gap-3 rounded-2xl border border-white/10 bg-white/[0.045] p-4">
              <ShieldIcon className="mt-0.5 size-5 shrink-0 text-cobalt-light" />
              <p className="text-xs leading-5 text-white/70">
                WriterFlow is ad-hoc signed and not notarized. macOS requires the
                documented <strong className="font-medium text-white/76">Open Anyway</strong>{" "}
                step on first launch — the install guide includes a one-click link to
                Security settings. The checksum verifies the downloaded bytes, not the
                publisher&apos;s identity.
              </p>
            </div>

            <Link
              className="mt-6 inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-paper underline decoration-white/25 underline-offset-4 transition-colors hover:decoration-white focus-ring"
              href="/install/"
            >
              Read the full installation guide
              <ArrowUpRightIcon className="size-4" />
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
}

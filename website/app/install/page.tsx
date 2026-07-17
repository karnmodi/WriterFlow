import type { Metadata } from "next";
import Link from "next/link";

import { ArrowUpRightIcon, ShieldIcon } from "@/components/Icons";
import { ReleaseActions } from "@/components/ReleaseActions";
import {
  release,
  releaseIsAvailable,
  releaseStatusCopy,
} from "@/lib/release";

export const metadata: Metadata = {
  title: "Install WriterFlow 1.0",
  description:
    "Download, verify, and install WriterFlow 1.0 on an Apple-silicon Mac.",
};

const steps = [
  {
    title: "Download the release",
    body: "Download both the DMG and its SHA-256 file so you can verify the package before opening it.",
  },
  {
    title: "Verify the DMG",
    body: "Keep both files in the same Downloads folder, open Terminal there, and run the command below. A successful check reports “OK.”",
  },
  {
    title: "Move WriterFlow to Applications",
    body: "Open the DMG and drag WriterFlow into Applications. Eject the mounted disk image when the copy finishes.",
  },
  {
    title: "Approve the first launch",
    body: "Open WriterFlow once, then go to System Settings → Privacy & Security and choose Open Anyway. Confirm the prompt to launch the unidentified app.",
  },
  {
    title: "Grant access and connect Azure",
    body: "Follow onboarding for Accessibility and Input Monitoring, then add your Azure OpenAI Responses endpoint, deployment names, and API key in Settings.",
  },
];

export default function InstallPage() {
  return (
    <main id="main-content">
      <section className="page-hero">
        <div className="page-orbit" />
        <div className="site-shell relative py-16 sm:py-24">
          <div className="max-w-4xl">
            <p className="section-kicker text-blue">Install WriterFlow {release.version}</p>
            <h1 className="mt-6 font-display text-[clamp(4rem,9vw,8rem)] leading-[0.86] tracking-[-0.065em] text-ink">
              From download
              <span className="block italic text-blue">to first rewrite.</span>
            </h1>
            <p className="mt-8 max-w-2xl text-lg leading-8 text-ink/60">
              A transparent path through download, checksum verification, macOS approval, and
              first-run permissions.
            </p>
            <ReleaseActions className="mt-9" />
            <p className="mt-5 max-w-2xl text-xs leading-5 text-ink/65">{releaseStatusCopy}</p>
          </div>
        </div>
      </section>

      <section className="border-t border-ink/10 bg-paper py-16 sm:py-24">
        <div className="site-shell grid gap-12 lg:grid-cols-[0.72fr_1.28fr] lg:gap-20">
          <aside className="lg:sticky lg:top-10 lg:self-start">
            <p className="section-kicker">Before you begin</p>
            <dl className="requirements-list mt-6">
              <div>
                <dt>macOS</dt>
                <dd>14 or later</dd>
              </div>
              <div>
                <dt>Mac</dt>
                <dd>Apple silicon only</dd>
              </div>
              <div>
                <dt>AI</dt>
                <dd>Your Azure OpenAI resource</dd>
              </div>
              <div>
                <dt>Updates</dt>
                <dd>Manual in v1</dd>
              </div>
            </dl>

            <div className="mt-7 flex gap-3 rounded-2xl bg-amber-soft/55 p-4 text-ink/62">
              <ShieldIcon className="mt-0.5 size-5 shrink-0 text-amber" />
              <p className="text-xs leading-5">
                Version 1.0 is ad-hoc signed and not notarized. Organization-managed Macs may
                block the Open Anyway override.
              </p>
            </div>
          </aside>

          <div>
            <ol className="install-steps">
              {steps.map((step, index) => (
                <li key={step.title}>
                  <span className="install-step-number">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <h2>{step.title}</h2>
                    <p>{step.body}</p>

                    {index === 0 ? <ReleaseActions className="mt-6" /> : null}

                    {index === 1 ? (
                      <div className="mt-6">
                        <div className="code-block">
                          <span aria-hidden="true" className="text-success">
                            $
                          </span>
                          <code>
                            (cd ~/Downloads &amp;&amp; shasum -a 256 -c{" "}
                            {release.checksumFilename})
                          </code>
                        </div>
                        <p className="mt-3 break-all text-[11px] leading-5 text-ink/65">
                          {releaseIsAvailable ? "Published" : "Current release-candidate"}{" "}
                          SHA-256: <code>{release.sha256}</code>
                        </p>
                      </div>
                    ) : null}
                  </div>
                </li>
              ))}
            </ol>

            <div className="mt-14 rounded-[1.75rem] bg-ink p-6 text-paper sm:p-9">
              <p className="section-kicker text-cobalt-light">What the checksum proves</p>
              <h2 className="mt-4 font-display text-3xl tracking-[-0.04em] sm:text-4xl">
                The bytes match. The identity does not.
              </h2>
              <p className="mt-5 max-w-2xl text-sm leading-6 text-white/70">
                A matching SHA-256 confirms that the DMG you downloaded is byte-for-byte the
                published release artifact. Because v1 is not Developer ID signed or notarized,
                the checksum does not establish an Apple-verified publisher identity.
              </p>
            </div>

            <div className="mt-10 flex flex-col gap-4 border-t border-ink/10 pt-8 sm:flex-row sm:items-center sm:justify-between">
              <p className="text-sm text-ink/65">Want to understand what leaves your Mac?</p>
              <Link
                className="inline-flex min-h-11 items-center gap-1.5 font-semibold text-ink underline decoration-blue/35 underline-offset-4 hover:decoration-blue focus-ring"
                href="/privacy/"
              >
                Read the privacy boundary
                <ArrowUpRightIcon className="size-4" />
              </Link>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}

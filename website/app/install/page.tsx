import type { Metadata } from "next";
import Link from "next/link";

import { ArrowUpRightIcon, CheckIcon, ShieldIcon } from "@/components/Icons";
import { ReleaseActions } from "@/components/ReleaseActions";
import { release, releaseHasDownload, releaseStatusCopy } from "@/lib/release";

export const metadata: Metadata = {
  title: "Install WriterFlow Cloud private beta",
  description:
    "A clear, user-focused path through download, verification, macOS permissions, account pairing, and your first rewrite.",
};

const steps = [
  ["Download both files", "Download the WriterFlow DMG and its SHA-256 file. Keep them together in Downloads."],
  ["Verify what you downloaded", "Open Terminal in Downloads and run the checksum command below. A correct download reports “OK.”"],
  ["Move WriterFlow to Applications", "Open the DMG, drag WriterFlow onto Applications, then eject the disk image."],
  ["Approve the first launch", "Open WriterFlow once. In System Settings → Privacy & Security, choose Open Anyway and confirm."],
  ["Grant the two permissions", "Follow onboarding for Accessibility and Input Monitoring. WriterFlow never records key contents and stays inert in secure fields."],
  ["Sign in and approve this Mac", "Open Dashboard → Account, choose Sign In, complete browser sign-in, and confirm the displayed device code."],
  ["Complete your first rewrite", "Type in a supported app, open WriterFlow, choose an action, review the preview, and replace only when you are ready."],
];

export default function InstallPage() {
  return (
    <main id="main-content">
      <section className="user-page-hero user-page-hero-lavender">
        <div className="user-page-orbit" aria-hidden="true" />
        <div className="site-shell user-page-hero-grid">
          <div>
            <p className="section-kicker text-blue">Install WriterFlow {release.version}</p>
            <h1>From download<br /><em>to your first rewrite.</em></h1>
          </div>
          <div className="user-page-summary">
            <p>
              Follow one clear path through package verification, macOS approval,
              permissions, sign-in, and device pairing.
            </p>
            <ReleaseActions className="mt-7" />
            <small>{releaseStatusCopy}</small>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-paper install-readiness-section">
        <div className="site-shell">
          <div className="readiness-strip" aria-label="WriterFlow installation requirements">
            <div><span>macOS</span><strong>14 or later</strong></div>
            <div><span>Mac</span><strong>Apple silicon</strong></div>
            <div><span>Account</span><strong>Private beta</strong></div>
            <div><span>Updates</span><strong>Manual</strong></div>
          </div>
          <div className="install-warning">
            <ShieldIcon className="size-5" />
            <p>
              WriterFlow is ad-hoc signed and not notarized during private beta.
              Organization-managed Macs may block the Open Anyway override.
            </p>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-soft">
        <div className="site-shell user-split-layout">
          <aside className="user-sticky-intro">
            <p className="section-kicker text-blue">Your setup</p>
            <h2>Seven steps, in order.</h2>
            <p>Complete each check before moving on. Nothing here changes your writing until you approve a replacement.</p>
          </aside>
          <ol className="setup-card-list">
            {steps.map(([title, body], index) => (
              <li className={index === 3 ? "surface-lavender" : index === 5 ? "surface-cobalt" : "surface-paper"} key={title}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                <div>
                  <h2>{title}</h2>
                  <p>{body}</p>
                  {index === 0 ? <ReleaseActions className="mt-6" /> : null}
                  {index === 1 ? (
                    <div className="mt-6">
                      <div className="code-block">
                        <span aria-hidden="true" className="text-success">$</span>
                        <code>(cd ~/Downloads &amp;&amp; shasum -a 256 -c {release.checksumFilename})</code>
                      </div>
                      <p className="checksum-copy">
                        {release.sha256 ? (
                          <>
                            {releaseHasDownload ? "Published" : "Current release-candidate"} SHA-256:{" "}
                            <code>{release.sha256}</code>
                          </>
                        ) : (
                          "The final SHA-256 will be published alongside the WriterFlow 2.0.0 DMG."
                        )}
                      </p>
                    </div>
                  ) : null}
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="user-page-section user-page-section-ink">
        <div className="site-shell proof-grid">
          <div>
            <p className="section-kicker text-cobalt-light">What the checksum tells you</p>
            <h2>The bytes match.<br /><em>The identity does not.</em></h2>
          </div>
          <div>
            <p>
              A matching SHA-256 confirms that your DMG is byte-for-byte the published artifact.
              Because the private beta is not Developer ID signed or notarized, it does not establish
              an Apple-verified publisher identity.
            </p>
            <p className="proof-point"><CheckIcon className="size-4" /> Matching checksum: correct file</p>
            <p className="proof-point"><ShieldIcon className="size-4" /> Open Anyway: still required</p>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-paper">
        <div className="site-shell user-next-card surface-lavender">
          <div>
            <span>Before you continue</span>
            <h2>See what leaves your Mac.</h2>
            <p>Read the privacy boundary before granting permissions or running your first cloud rewrite.</p>
          </div>
          <Link className="user-page-action" href="/privacy/">
            Read the privacy guide <ArrowUpRightIcon className="size-4" />
          </Link>
        </div>
      </section>
    </main>
  );
}

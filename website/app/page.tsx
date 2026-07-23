import Link from "next/link";

import { DownloadPanel } from "@/components/DownloadPanel";
import { ArrowUpRightIcon, CheckIcon, ShieldIcon, SparkIcon } from "@/components/Icons";
import { ReleaseActions } from "@/components/ReleaseActions";
import { RewriteStudio } from "@/components/RewriteStudio";
import {
  release,
  releaseIsAvailable,
  releaseIsPrivateBeta,
  releaseStatusCopy,
} from "@/lib/release";

const benefits = [
  ["In your context", "Rewrite inside Gmail, Slack, WhatsApp, and the places you already work."],
  ["Always adjustable", "Change the tone, length, or intent without restarting your thought."],
  ["You stay in control", "Preview every result, then replace, copy, retry, or simply close it."],
];

export default function Home() {
  const schema = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "WriterFlow",
    applicationCategory: "ProductivityApplication",
    operatingSystem: "macOS 14 or later on Apple silicon",
    softwareVersion: release.version,
    ...(releaseIsAvailable ? { offers: { "@type": "Offer", price: "0", priceCurrency: "USD" } } : {}),
  };

  return (
    <main id="main-content">
      <script dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }} type="application/ld+json" />

      <section className="new-hero">
        <div className="hero-aurora" aria-hidden="true" />
        <div className="site-shell hero-inner">
          <div className="hero-copy reveal-up">
            <div className="release-eyebrow">
              <span className="size-2 rounded-full bg-success" />
              WriterFlow {release.version} · Native for macOS
            </div>
            <h1>Say it your way.<br /><em>Only better.</em></h1>
            <p>
              A writing assistant that meets you wherever you type. Turn rough thoughts into
              clear, natural writing without breaking your flow.
            </p>
            <ReleaseActions className="mt-8" />
            <div className="hero-proof sm:items-center md:gap-x-6">
              <span><CheckIcon className="size-4" /> Review before replacing</span>
              <span><ShieldIcon className="size-4" /> Explicit action only</span>
              <span>WriterFlow account required for cloud actions</span>
            </div>
          </div>

          <div className="hero-mini-card reveal-up reveal-delay-2" aria-hidden="true">
            <span className="mini-label">WriterFlow · Formal</span>
            <p className="mini-before">can we maybe push the meeting?</p>
            <div className="mini-flow"><SparkIcon className="size-4" /><i /></div>
            <p>Would it be possible to reschedule our meeting?</p>
            <span className="mini-ready"><CheckIcon className="size-3.5" /> Ready to replace</span>
          </div>
        </div>
      </section>

      <section className="studio-section" id="try-it">
        <div className="site-shell">
          <div className="section-intro">
            <span className="section-kicker">Try the flow</span>
            <h2>One workspace. Every revision.</h2>
            <p>There’s no rigid wizard. Edit the draft or switch preferences in any order—the result follows you.</p>
          </div>
          <RewriteStudio />
        </div>
      </section>

      <section className="benefit-section" id="how-it-works">
        <div className="site-shell">
          <div className="benefit-heading">
            <span className="section-kicker">Made for momentum</span>
            <h2>Less managing words.<br />More moving ideas.</h2>
          </div>
          <div className="benefit-grid">
            {benefits.map(([title, body], index) => (
              <article key={title}>
                <span>0{index + 1}</span>
                <h3>{title}</h3>
                <p>{body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="privacy-band">
        <div className="site-shell privacy-band-inner">
          <div className="privacy-orb"><ShieldIcon className="size-8" /></div>
          <div>
            <span className="section-kicker">Private by design</span>
            <h2>Your words don’t move until you do.</h2>
          </div>
          <div>
            <p>
              Passive typing never sends text. WriterFlow only processes the draft and visible
              context required after you choose an action. Inference content is ephemeral and
              is not added to your account record.
            </p>
            <Link href="/privacy/">Explore the data boundary <ArrowUpRightIcon className="size-4" /></Link>
          </div>
        </div>
      </section>

      {!releaseIsAvailable ? (
        <aside className="release-disclosure" aria-label="Release status">
          <div className="site-shell">
            <p>
              <strong>{releaseIsPrivateBeta ? "Cloud private beta" : "Release testing"}</strong>
              {" — "}
              {releaseStatusCopy}
            </p>
            <Link href="/#download">View release details</Link>
          </div>
        </aside>
      ) : null}

      <DownloadPanel />
    </main>
  );
}

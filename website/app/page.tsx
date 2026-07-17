import Link from "next/link";

import { DownloadPanel } from "@/components/DownloadPanel";
import {
  ArrowUpRightIcon,
  CheckIcon,
  ChevronRightIcon,
  ShieldIcon,
  SparkIcon,
} from "@/components/Icons";
import { ProductStage } from "@/components/ProductStage";
import { ReleaseActions } from "@/components/ReleaseActions";
import {
  release,
  releaseIsAvailable,
  releaseStatusCopy,
} from "@/lib/release";

const flowSteps = [
  {
    number: "01",
    title: "Stay in your flow",
    body: "A small WriterFlow mark appears beside supported editable fields, or open it with ⌃⌥ Space.",
  },
  {
    number: "02",
    title: "Choose the change",
    body: "Elaborate, shift tone, fix grammar, draft a reply, or describe exactly what you need.",
  },
  {
    number: "03",
    title: "You make the call",
    body: "Read the streamed preview. Replace, copy, retry, or discard — your draft changes only when you say so.",
  },
];

const localFacts = [
  "History, snippets, voice profile, and app rules",
  "Password and secure fields are ignored",
  "Passive typing never records key contents",
];

const cloudFacts = [
  "Text needed for an action or recommendation",
  "Only your configured Azure OpenAI resource",
  "No WriterFlow account, remote user database, or cloud API",
];

export default function Home() {
  const softwareApplicationSchema = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "WriterFlow",
    applicationCategory: "ProductivityApplication",
    operatingSystem: "macOS 14 or later on Apple silicon",
    softwareVersion: release.version,
    description:
      "A native macOS writing assistant for rewrites, grammar fixes, and contextual replies.",
    ...(releaseIsAvailable
      ? {
          offers: {
            "@type": "Offer",
            price: "0",
            priceCurrency: "USD",
            description: "The app is free to download. Azure OpenAI usage may incur charges.",
          },
        }
      : {}),
  };

  return (
    <main id="main-content">
      <script
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationSchema) }}
        type="application/ld+json"
      />

      <section className="hero-section overflow-hidden">
        <div className="hero-flow-line" />
        <div className="site-shell relative grid min-h-[calc(100svh-120px)] items-center gap-12 py-14 md:min-h-[calc(100svh-76px)] lg:grid-cols-[0.84fr_1.16fr] lg:gap-7 lg:py-20">
          <div className="relative z-10 max-w-2xl reveal-up">
            <div className="release-eyebrow">
              <span
                aria-hidden="true"
                className={`size-2 rounded-full ${
                  releaseIsAvailable ? "bg-success" : "bg-amber"
                }`}
              />
              WriterFlow {release.version}
              <span className="text-ink/24">/</span>
              {releaseIsAvailable ? "Public release" : "Final release testing"}
            </div>

            <h1 className="mt-7 font-display text-[clamp(4rem,8.4vw,8.4rem)] leading-[0.84] tracking-[-0.07em] text-ink">
              Write better,
              <span className="block text-blue italic">where you type.</span>
            </h1>

            <p className="mt-8 max-w-xl text-lg leading-8 text-ink/62 sm:text-xl">
              Rewrite drafts, fix grammar, and create contextual replies without leaving the
              app you&apos;re in. WriterFlow keeps the work in place — and keeps you in control.
            </p>

            <ReleaseActions className="mt-9" />

            <p className="mt-5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs font-medium text-ink/65">
              <span>Free download</span>
              <span aria-hidden="true">·</span>
              <span>{release.minimumMacOS}</span>
              <span aria-hidden="true">·</span>
              <span>{release.architecture}</span>
              <span aria-hidden="true">·</span>
              <span>Your Azure OpenAI resource required</span>
            </p>
          </div>

          <div className="relative z-0 reveal-up reveal-delay-2">
            <ProductStage />
          </div>
        </div>

        <div className="site-shell pb-8 sm:pb-12">
          <div className="trust-rail" aria-label="WriterFlow product principles">
            <span>Native macOS</span>
            <span>Review before replace</span>
            <span>Local history</span>
            <span>No WriterFlow account</span>
          </div>
        </div>
      </section>

      <section className="border-t border-ink/10 bg-paper py-20 sm:py-28" id="how-it-works">
        <div className="site-shell">
          <div className="grid gap-8 lg:grid-cols-[0.85fr_1.15fr] lg:gap-20">
            <div>
              <p className="section-kicker">One small shift</p>
              <h2 className="mt-5 max-w-xl font-display text-[clamp(3.2rem,6vw,6rem)] leading-[0.91] tracking-[-0.055em] text-ink">
                Less tab-hopping.
                <span className="block text-blue italic">More finished thoughts.</span>
              </h2>
            </div>
            <div className="lg:pt-8">
              <p className="max-w-xl text-lg leading-8 text-ink/60">
                WriterFlow turns the copy-paste-rewrite loop into one short decision. It sits
                beside your draft, can use visible context when the app exposes it, and lets
                you approve the result before anything changes.
              </p>
              <Link
                className="mt-6 inline-flex min-h-11 items-center gap-1 text-sm font-semibold text-ink underline decoration-blue/35 underline-offset-4 transition-colors hover:decoration-blue focus-ring"
                href="/privacy/"
              >
                See the data boundary
                <ArrowUpRightIcon className="size-4" />
              </Link>
            </div>
          </div>

          <ol className="flow-steps mt-16 sm:mt-20">
            {flowSteps.map((step) => (
              <li className="flow-step" key={step.number}>
                <span className="flow-number">{step.number}</span>
                <div>
                  <h3 className="text-xl font-semibold tracking-[-0.03em] text-ink">
                    {step.title}
                  </h3>
                  <p className="mt-3 max-w-sm text-sm leading-6 text-ink/65">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="showcase-section py-20 sm:py-28">
        <div className="site-shell">
          <div className="showcase-frame">
            <div className="showcase-copy">
              <p className="section-kicker text-blue">A calmer way to revise</p>
              <h2 className="mt-5 max-w-md font-display text-[clamp(3.2rem,5.7vw,5.8rem)] leading-[0.9] tracking-[-0.055em] text-ink">
                Your first thought,
                <span className="block italic text-blue">only clearer.</span>
              </h2>
              <p className="mt-7 max-w-md text-base leading-7 text-ink/65">
                Shift tone without flattening your voice. Build replies from the conversation
                already on screen. Save the result only when it feels right.
              </p>

              <ul className="mt-9 space-y-4">
                {[
                  "Tone, grammar, replies, and custom prompts",
                  "A streamed preview before any text is replaced",
                  "Per-app preferences and personal writing context",
                ].map((item) => (
                  <li className="flex gap-3 text-sm font-medium text-ink/72" key={item}>
                    <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-blue/10 text-blue">
                      <CheckIcon className="size-4" />
                    </span>
                    {item}
                  </li>
                ))}
              </ul>
            </div>

            <div className="rewrite-canvas" aria-label="A before and after writing example">
              <div className="rewrite-meta">
                <span>Draft in progress</span>
                <span>⌃⌥ Space</span>
              </div>
              <div className="rewrite-before">
                <p className="rewrite-label">Before</p>
                <p>
                  hey everyone just wanted to say the timeline changed and we probably need
                  another day to make sure everything is ready
                </p>
              </div>
              <div className="rewrite-divider">
                <span className="flex size-9 items-center justify-center rounded-full bg-blue text-white shadow-lg shadow-blue/20">
                  <SparkIcon className="size-4.5" />
                </span>
                <span className="h-px flex-1 bg-ink/10" />
                <span className="text-[10px] font-semibold tracking-[0.12em] text-blue uppercase">
                  Clear + concise
                </span>
              </div>
              <div className="rewrite-after">
                <p className="rewrite-label text-blue">After</p>
                <p>
                  Quick update: the timeline has shifted by one day so we can make sure
                  everything is ready for launch.
                </p>
                <span className="mt-6 inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-xs font-semibold text-white">
                  <CheckIcon className="size-4" />
                  Ready to replace
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="privacy-ledger py-20 text-paper sm:py-28">
        <div className="site-shell">
          <div className="grid gap-12 lg:grid-cols-[0.8fr_1.2fr] lg:gap-20">
            <div>
              <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-white/15 bg-white/8 text-cobalt-light">
                <ShieldIcon className="size-6" />
              </span>
              <p className="section-kicker mt-7 text-cobalt-light">A visible boundary</p>
              <h2 className="mt-5 max-w-xl font-display text-[clamp(3.1rem,5.5vw,5.7rem)] leading-[0.91] tracking-[-0.055em]">
                Local where it matters. Cloud only when you ask.
              </h2>
              <p className="mt-7 max-w-lg text-base leading-7 text-white/70">
                No WriterFlow account, subscription, payment system, remote user database, or
                custom WriterFlow API. Your Azure credential is stored in macOS Keychain and
                used only for allowlisted HTTPS requests to Azure; no shared publisher key
                ships in the app.
              </p>
            </div>

            <div className="boundary-ledger">
              <div className="boundary-column">
                <p className="boundary-label">
                  <span className="size-2 rounded-full bg-success" />
                  Stays on your Mac
                </p>
                <ul>
                  {localFacts.map((fact) => (
                    <li key={fact}>{fact}</li>
                  ))}
                </ul>
              </div>
              <div className="boundary-column">
                <p className="boundary-label">
                  <span className="size-2 rounded-full bg-cobalt-light" />
                  Sent on explicit interaction
                </p>
                <ul>
                  {cloudFacts.map((fact) => (
                    <li key={fact}>{fact}</li>
                  ))}
                </ul>
              </div>
              <div className="col-span-full border-t border-white/10 pt-6">
                <p className="text-xs leading-5 text-white/68">
                  Opening the action menu can send the current field text for an action
                  recommendation. Running an action can send selected text, visible
                  conversation context, your instruction, and enabled personalization.
                </p>
                <Link
                  className="mt-5 inline-flex min-h-11 items-center gap-1 text-sm font-semibold text-paper underline decoration-white/25 underline-offset-4 hover:decoration-white focus-ring"
                  href="/privacy/"
                >
                  Read the v1 privacy details
                  <ChevronRightIcon className="size-4" />
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>

      {!releaseIsAvailable ? (
        <aside className="bg-amber-soft py-4" aria-label="Release status">
          <div className="site-shell flex flex-col gap-2 text-sm text-ink/68 sm:flex-row sm:items-center sm:justify-between">
            <p className="font-medium">{releaseStatusCopy}</p>
            <Link className="shrink-0 font-semibold text-ink underline underline-offset-4" href="/#download">
              View the release ticket
            </Link>
          </div>
        </aside>
      ) : null}

      <DownloadPanel />
    </main>
  );
}

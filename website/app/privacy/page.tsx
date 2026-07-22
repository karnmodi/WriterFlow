import type { Metadata } from "next";
import Link from "next/link";

import { ArrowUpRightIcon, CheckIcon, ShieldIcon } from "@/components/Icons";

export const metadata: Metadata = {
  title: "Privacy in WriterFlow 1.0",
  description:
    "A plain-language explanation of WriterFlow's local data, Azure AI requests, permissions, and credentials.",
};

const absentInfrastructure = [
  "No WriterFlow payment charged in v1.0 (v2 alpha adds optional account sign-in)",
  "No remote WriterFlow personalization database synced by default",
  "No shared AI credential bundled with the app",
];

export default function PrivacyPage() {
  return (
    <main id="main-content">
      <section className="privacy-page-hero text-paper">
        <div className="privacy-page-grid" />
        <div className="site-shell relative py-16 sm:py-24">
          <div className="grid gap-10 lg:grid-cols-[0.95fr_1.05fr] lg:items-end lg:gap-20">
            <div>
              <span className="inline-flex size-12 items-center justify-center rounded-2xl border border-white/15 bg-white/8 text-cobalt-light">
                <ShieldIcon className="size-6" />
              </span>
              <p className="section-kicker mt-7 text-cobalt-light">Privacy in v1.0</p>
              <h1 className="mt-6 font-display text-[clamp(4rem,8.5vw,8rem)] leading-[0.86] tracking-[-0.065em]">
                A boundary
                <span className="block italic text-cobalt-light">you can see.</span>
              </h1>
            </div>
            <p className="max-w-xl pb-2 text-lg leading-8 text-white/70">
              WriterFlow keeps personal app data on your Mac and sends writing content only
              through explicit interactions with the assistant. v1 connects directly to the
              Azure OpenAI resource you configure — there is no WriterFlow cloud in between.
            </p>
          </div>
        </div>
      </section>

      <section className="bg-paper py-16 sm:py-24">
        <div className="site-shell">
          <div className="privacy-detail-grid">
            <article className="privacy-detail privacy-detail-wide">
              <p className="detail-number">01 / Local data</p>
              <h2>Your writing profile stays with your Mac.</h2>
              <p>
                History, personalization, voice profile, snippets, saved facts, per-app rules,
                usage records, and settings are stored locally. Diagnostics are exported only
                when you choose to create a local report; WriterFlow does not upload them.
              </p>
            </article>

            <article className="privacy-detail">
              <p className="detail-number">02 / Passive typing</p>
              <h2>No inference while you simply type.</h2>
              <p>
                Input Monitoring is used only for a local “is typing” signal. WriterFlow does
                not inspect, buffer, or record key contents, and passive typing does not trigger
                a network request.
              </p>
            </article>

            <article className="privacy-detail privacy-detail-blue">
              <p className="detail-number">03 / Explicit interaction</p>
              <h2>The cloud boundary begins at the action menu.</h2>
              <p>
                Opening the action menu can send the current field text to Azure to recommend
                an action. Running an action can send selected or full field text, visible
                conversation context, your instruction, and enabled personalization. Choosing
                Analyze My Writing Style can send up to 20 accepted outputs for analysis.
              </p>
            </article>

            <article className="privacy-detail">
              <p className="detail-number">04 / Credentials</p>
              <h2>Your Azure key is never a WriterFlow release asset.</h2>
              <p>
                Your API key is stored in macOS Keychain and included only in HTTPS requests to
                allowlisted Azure hosts. It is not written to settings files, logs, source code,
                the DMG, or a WriterFlow service. No publisher AI key ships with the app.
              </p>
            </article>

            <article className="privacy-detail privacy-detail-wide privacy-detail-dark">
              <div>
                <p className="detail-number text-cobalt-light">05 / Not part of v1</p>
                <h2>A smaller system is easier to understand.</h2>
              </div>
              <ul>
                {absentInfrastructure.map((item) => (
                  <li key={item}>
                    <CheckIcon className="size-4 shrink-0 text-success" />
                    {item}
                  </li>
                ))}
              </ul>
            </article>
          </div>

          <div className="mt-14 grid gap-8 border-t border-ink/12 pt-12 lg:grid-cols-2 lg:gap-16">
            <div>
              <p className="section-kicker">Secure fields</p>
              <h2 className="mt-4 font-display text-4xl tracking-[-0.04em] text-ink">
                Passwords are out of bounds.
              </h2>
              <p className="mt-5 text-sm leading-6 text-ink/65">
                WriterFlow is inert in secure password fields. Password-manager apps are
                excluded by default, and you can pause WriterFlow or exclude additional apps at
                any time.
              </p>
            </div>
            <div>
              <p className="section-kicker">Costs and control</p>
              <h2 className="mt-4 font-display text-4xl tracking-[-0.04em] text-ink">
                Free app. Your Azure bill.
              </h2>
              <p className="mt-5 text-sm leading-6 text-ink/65">
                WriterFlow does not bill you. Azure OpenAI usage is charged to the Azure account
                behind the resource you configure, according to your provider agreement and
                deployment pricing.
              </p>
            </div>
          </div>

          <div className="mt-14 flex flex-col gap-4 rounded-[1.75rem] bg-paper-deep p-6 sm:flex-row sm:items-center sm:justify-between sm:p-8">
            <p className="max-w-xl text-sm leading-6 text-ink/65">
              Ready to install? The guide includes the checksum command and the first-launch
              macOS approval flow.
            </p>
            <Link
              className="inline-flex min-h-11 shrink-0 items-center gap-1.5 font-semibold text-ink underline decoration-blue/35 underline-offset-4 hover:decoration-blue focus-ring"
              href="/install/"
            >
              Open the install guide
              <ArrowUpRightIcon className="size-4" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}

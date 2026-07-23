import type { Metadata } from "next";
import Link from "next/link";

import { ArrowUpRightIcon, CheckIcon, ShieldIcon } from "@/components/Icons";

export const metadata: Metadata = {
  title: "Privacy in WriterFlow Cloud private beta",
  description:
    "Understand what WriterFlow reads, what stays on your Mac, what reaches the cloud, and the controls available to you.",
};

const quickAnswers = [
  ["While you type", "Nothing is uploaded. WriterFlow only notices that typing is active."],
  ["When you choose an action", "The draft and the minimum visible context needed for that request are processed."],
  ["After the rewrite", "Inference content is ephemeral by default; account and usage metadata remain."],
];

const journey = [
  {
    label: "On your Mac",
    title: "Your writing profile remains local",
    body: "History, personalization, voice profile, snippets, saved facts, app rules, and settings stay in an account-scoped SQLCipher database.",
    tone: "paper",
  },
  {
    label: "While you type",
    title: "WriterFlow does not record your keys",
    body: "Input Monitoring provides a local “is typing” signal only. It does not inspect, buffer, or log key contents, and it never starts inference.",
    tone: "lavender",
  },
  {
    label: "When you ask",
    title: "You decide when processing begins",
    body: "Choosing an action can send the field text, relevant visible conversation context, your instruction, and a bounded app-tone signal. You review the result before anything is replaced.",
    tone: "cobalt",
  },
  {
    label: "In WriterFlow Cloud",
    title: "Account state persists; writing content does not",
    body: "WriterFlow stores account, organization, device, entitlement, and metadata-only usage records. Raw drafts, prompts, context, and generated output are ephemeral by default.",
    tone: "ink",
  },
];

export default function PrivacyPage() {
  return (
    <main id="main-content">
      <section className="user-page-hero user-page-hero-ink">
        <div className="user-page-orbit" aria-hidden="true" />
        <div className="site-shell user-page-hero-grid">
          <div>
            <span className="user-page-icon"><ShieldIcon className="size-6" /></span>
            <p className="section-kicker">Your privacy</p>
            <h1>Know exactly<br /><em>what leaves your Mac.</em></h1>
          </div>
          <div className="user-page-summary">
            <p>
              WriterFlow stays quiet until you ask it to help. Your local writing profile
              remains encrypted on your Mac, and every rewrite stays reviewable before replacement.
            </p>
            <a className="user-page-jump" href="#privacy-journey">Follow your text through WriterFlow</a>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-paper">
        <div className="site-shell">
          <header className="user-section-heading">
            <div>
              <p className="section-kicker text-blue">The short answer</p>
              <h2>Three moments.<br /><em>Three clear boundaries.</em></h2>
            </div>
            <p>You should not need technical documentation to understand when your writing moves.</p>
          </header>
          <div className="answer-grid">
            {quickAnswers.map(([title, body], index) => (
              <article key={title}>
                <span>0{index + 1}</span>
                <h3>{title}</h3>
                <p>{body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-soft" id="privacy-journey">
        <div className="site-shell user-split-layout">
          <aside className="user-sticky-intro">
            <p className="section-kicker text-blue">Follow your text</p>
            <h2>From typing to replacement.</h2>
            <p>Each surface colour marks a different kind of moment, while the words explain the actual boundary.</p>
          </aside>
          <div className="boundary-list">
            {journey.map((item, index) => (
              <article className={`boundary-card surface-${item.tone}`} key={item.title}>
                <span>0{index + 1} / {item.label}</span>
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-paper">
        <div className="site-shell">
          <header className="user-section-heading">
            <div>
              <p className="section-kicker">Controls you keep</p>
              <h2>You remain in charge.</h2>
            </div>
          </header>
          <div className="control-grid">
            <article>
              <CheckIcon className="size-5" />
              <h3>Secure fields stay out of bounds</h3>
              <p>WriterFlow is inert in password fields. Password-manager apps are excluded by default.</p>
            </article>
            <article>
              <CheckIcon className="size-5" />
              <h3>Your Mac can be revoked</h3>
              <p>Browser sign-in creates a revocable WriterFlow device token stored in macOS Keychain—not your password.</p>
            </article>
            <article>
              <CheckIcon className="size-5" />
              <h3>You can pause or exclude apps</h3>
              <p>Pause WriterFlow at any time or add applications where you do not want the floating assistant to appear.</p>
            </article>
            <article>
              <CheckIcon className="size-5" />
              <h3>Billing remains disabled</h3>
              <p>Private-beta usage totals support allowance enforcement. No payment is charged and Stripe billing is inactive.</p>
            </article>
          </div>
          <div className="user-next-card surface-lavender">
            <div>
              <span>Next step</span>
              <h2>Ready to set up WriterFlow?</h2>
              <p>The install guide covers download verification, macOS permissions, account pairing, and your first rewrite.</p>
            </div>
            <Link className="user-page-action" href="/install/">
              Open the install guide <ArrowUpRightIcon className="size-4" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}

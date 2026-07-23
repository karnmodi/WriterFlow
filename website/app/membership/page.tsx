import type { Metadata } from "next";
import Link from "next/link";

import { CheckIcon, ShieldIcon } from "@/components/Icons";
import { membershipFeatureLabels, membershipPlans } from "@/lib/membership-plans";

export const metadata: Metadata = {
  title: "Membership",
  description: "Understand your current WriterFlow allowance and what the upcoming Pro plan may add.",
};

export default function MembershipPage() {
  return (
    <main id="main-content">
      <section className="user-page-hero user-page-hero-cobalt">
        <div className="user-page-orbit" aria-hidden="true" />
        <div className="site-shell user-page-hero-grid">
          <div>
            <p className="section-kicker">Your membership</p>
            <h1>Start with 500 units.<br /><em>Decide later.</em></h1>
          </div>
          <div className="user-page-summary">
            <p>
              Every WriterFlow account currently starts on Free. Pro remains in development,
              and no upgrade or payment can happen until exact terms are published.
            </p>
            <Link className="user-page-jump" href="/account">View your current usage</Link>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-paper">
        <div className="site-shell">
          <header className="user-section-heading">
            <div>
              <p className="section-kicker text-blue">Choose with context</p>
              <h2>Your plan today.<br /><em>What may come next.</em></h2>
            </div>
            <p>Free is available now. Pro is shown beside it for clarity, not as an active sales offer.</p>
          </header>

          <div className="membership-grid membership-grid-v2">
            {membershipPlans.map((plan) => (
              <article className={`membership-card membership-card-${plan.id}`} key={plan.id}>
                <header>
                  <div>
                    <span>{plan.availability === "available" ? "Your available plan" : "In development"}</span>
                    <h2>{plan.tierName}</h2>
                  </div>
                  <p>
                    {plan.priceCents === 0 ? (
                      <><strong>£0</strong><small>No payment details</small></>
                    ) : (
                      <><strong>Not priced</strong><small>No billing yet</small></>
                    )}
                  </p>
                </header>

                <div className="membership-allowance">
                  <span>Included allowance</span>
                  <strong>{plan.unitAllowance === null ? "To be confirmed" : `${plan.unitAllowance} units`}</strong>
                  <small>{plan.billingCadence ? `Expected ${plan.billingCadence} cadence` : "Current free allowance"}</small>
                </div>

                <ul>
                  {plan.featureFlags.map((feature) => (
                    <li key={feature}>
                      <CheckIcon className="size-4" />
                      <span>{membershipFeatureLabels[feature]}</span>
                    </li>
                  ))}
                </ul>

                {plan.availability === "available" ? (
                  <Link className="membership-action" href="/account">View your account</Link>
                ) : (
                  <button className="membership-action" disabled type="button">Upgrade unavailable</button>
                )}
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-soft">
        <div className="site-shell membership-explainer">
          <div>
            <p className="section-kicker text-blue">How units work</p>
            <h2>A simple allowance,<br /><em>not provider tokens.</em></h2>
          </div>
          <div className="membership-explainer-list">
            <article><span>01</span><h3>Use WriterFlow normally</h3><p>Successful cloud actions consume WriterFlow units. Failed or cancelled delivery does not debit your allowance.</p></article>
            <article><span>02</span><h3>See one clear total</h3><p>Your Account page shows included and used units without exposing model names, provider tokens, or raw infrastructure costs.</p></article>
            <article><span>03</span><h3>Review before any paid plan</h3><p>Pro pricing, allowance, trial availability, and billing cadence will be confirmed before checkout becomes available.</p></article>
          </div>
        </div>
      </section>

      <section className="user-page-section user-page-section-ink">
        <div className="site-shell membership-safety">
          <ShieldIcon className="size-6" />
          <div>
            <p className="section-kicker text-cobalt-light">Private-beta status</p>
            <h2>Billing unavailable.</h2>
            <p>
              Pro checkout, trials, metered overages, and team billing are inactive.
              WriterFlow will show exact terms and request explicit approval before any paid membership begins.
            </p>
          </div>
          <Link className="user-page-action user-page-action-light" href="/account">Open your account</Link>
        </div>
      </section>
    </main>
  );
}

# ADR-0010: No Apple Developer account; v2 continues ad-hoc distribution

**Status:** Accepted
**Date:** 2026-07-18
**Phase:** 5 — Cloud foundation
**Supersedes:** ADR-0008

## Context

ADR-0008 made a paid Apple Developer ID a hard, never-revisit prerequisite for v2.
Its rationale was almost entirely driven by *in-app* OAuth: a registered Entra
redirect URI whose continuity depends on a stable signing identity, and MSAL's
shared **Keychain access group**, which requires a stable Apple Team ID prefix.

Two product decisions remove that rationale:

1. The owner will **not** acquire an Apple Developer Program membership ($99/year)
   for v2.
2. Authentication and membership move entirely into the browser; the Mac app is no
   longer an OAuth client and no longer embeds MSAL (ADR-0011). There is therefore
   no Entra redirect URI to keep continuous and no shared Keychain access group to
   validate against a Team ID.

What remains without a Developer ID is purely a distribution/Gatekeeper concern,
which v1 already ships against: ad-hoc-signed, non-notarized, manual approval.

## Decision

WriterFlow v2 is distributed exactly as v1 was: an ARM64 **ad-hoc-signed** app in a
DMG, published with a SHA-256 checksum, opened via documented **manual Gatekeeper
approval**, and updated by **manual download**. No Apple Developer ID, no
notarization, no stapling, and no Sparkle auto-update mechanism is required or
acquired for v2. WriterFlow-issued device tokens (ADR-0012) are stored in the app's
own Keychain item (no access group), so no Team-ID-scoped Keychain sharing is
needed.

## Consequences

- **Install/update friction.** On macOS Sequoia/Tahoe an ad-hoc app cannot be opened
  from the Gatekeeper dialog; the user must approve it in System Settings ›
  Privacy & Security, and again after each update. This friction is now attached to a
  *paid* product and must be documented prominently in onboarding and on the install
  page.
- **Security fixes ship by manual update.** Without notarization there is no
  warning-free auto-update; the release process must make manual updates easy to
  discover (checksum + install page, matching the v1 runbook).
- **Keychain durability is best-effort.** A WriterFlow refresh token in the app's own
  Keychain item may not survive every ad-hoc rebuild/update. Loss is *recoverable* by
  re-pairing in the browser (ADR-0011); it must never look like data loss, and it
  never affects the local SQLCipher DB key (ADR-0004), which is a separate item.
- **Tampering cost is lower** than a signed build, but this changes nothing about the
  trust model: the client is already treated as untrusted and all authorization is
  server-side (ADR-0005, threat model §2).
- Stage 8.4's Developer ID / notarization / Sparkle gate is **removed** from the v2
  release criteria and replaced by the v1-equivalent ad-hoc release gate.

## Revisit when

The Gatekeeper friction measurably harms paid conversion/retention, or a
distribution channel requires notarization — at which point acquiring a Developer ID
is a reversible cost decision, not an architectural rewrite, because auth no longer
depends on it.

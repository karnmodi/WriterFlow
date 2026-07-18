# ADR-0008: A stable Developer ID identity is required before external Phase 5 alpha

**Status:** Superseded by ADR-0010 (2026-07-18)
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

> **Superseded.** This ADR assumed in-app MSAL OAuth (ADR-0002), whose registered
> redirect URI and shared Keychain access group were the reasons a Developer ID was
> mandatory. ADR-0011 moves auth to the browser and removes MSAL from the app, and
> ADR-0010 accordingly drops the Apple Developer account requirement and keeps v1's
> ad-hoc distribution for v2. The historical reasoning below is retained for context.

## Context

V1 shipped ad-hoc signed with no Apple Developer Program membership, which was
acceptable because there was no OAuth callback, no persisted auth token, and no
migrated user data at stake (`RELEASE.md`). V2 introduces all three: an OAuth
redirect URI registered with Entra External ID, MSAL's Keychain-backed token
cache, and an atomic, one-time local data migration. Ad-hoc signing identity can
change between builds, which would break registered callback continuity and
Keychain access-group behavior in ways that are indistinguishable from real
account/data loss.

## Decision

Establish a stable Apple Developer ID Application signing identity before any
external Phase 5 alpha that performs real sign-in or migrates real local data.
Ad-hoc identity remains acceptable for local development only. Full notarization,
ticket stapling, and the Sparkle update mechanism remain a later Stage 8.4 gate —
this ADR only fixes the signing *identity*, not the full distribution pipeline.

## Consequences

- Apple Developer Program membership ($99/year) must be acquired before Stage 5.2
  proceeds to real MSAL/Keychain integration testing and before any alpha cohort
  outside the core dev machine.
- Stage 5.2's callback-URI, Keychain access-group, and broker/no-broker validation
  must be tested across bundled, installed, relocated, Developer ID-signed, and
  relaunched builds — not only debug runs — per the phase-5 checklist.
- Notarization/stapling/Sparkle remain explicitly out of scope until Stage 8.4;
  this ADR does not pull that work forward.

## Revisit when

Never, before GA — this is a hard prerequisite gate, not a reversible choice.

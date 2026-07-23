# ADR-0015: Use Developer APIM for the private beta

**Status:** Accepted  
**Date:** 2026-07-23  
**Phase:** 5 — Production cloud private beta

## Context

ADR-0005 selected Standard v2 APIM so the gateway could reach a completely
private Container Apps origin. Its current fixed price is approximately
USD 700/month per environment. That cost does not provide Azure OpenAI model
access: GlobalStandard model deployments are Azure-hosted and billed per token,
without WriterFlow provisioning GPU servers or reserved PTUs.

The private beta needs authenticated cloud inference and a controlled gateway,
but its traffic and SLA do not justify Standard v2's private-origin premium.

## Decision

- Use the existing Developer APIM gateway for the private beta.
- Keep the Container Apps API internet-routable, but require a random
  Key Vault-backed origin credential on every `/v2` request. APIM injects it;
  direct origin requests fail with 403 before route handling.
- Reuse the beta's public Azure service endpoints with their service-layer
  controls: PostgreSQL TLS plus firewall and least-privilege roles, Key Vault
  RBAC, and Azure OpenAI managed identity with local/API-key authentication
  disabled. Private endpoints remain part of the deferred Standard v2 profiles.
- Use Azure OpenAI GlobalStandard pay-per-token deployments with managed
  identity. Do not buy provisioned throughput or deploy WriterFlow model compute.
- Retain `staging-private` and `production-private` Bicep profiles as deferred,
  explicit upgrades. Private-beta automation always selects
  `private-beta-public` and cannot select Standard v2.

## Consequences

- The beta avoids a new approximately USD 700/month APIM unit.
- Developer APIM has no production SLA and is not a long-term general-availability
  edge. Cohort size and support promises must reflect that.
- The public origin credential, application JWT/device authorization, rate limits,
  and direct-origin negative probe are release gates.
- Standard v2 is reconsidered when paid usage, SLA requirements, compliance, or
  attack volume justify private-origin networking.

## Supersedes

For the private-beta environment only, this ADR supersedes ADR-0005's Standard v2
and private Container Apps origin decision. ADR-0005 remains the intended future
production topology after its cost gate is justified.

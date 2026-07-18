# ADR-0006: Azure OpenAI access uses managed identity and private endpoints only

**Status:** Accepted
**Date:** 2026-07-17
**Phase:** 5 — Cloud foundation

## Context

V1's BYO model required every user to hold their own Azure OpenAI key. V2 funds
shared cloud inference, which means a reusable provider credential now exists
somewhere — but it must never be reachable from, or embedded in, the Mac app, and
public network access to the model resource must not exist at all.

## Decision

Azure OpenAI resources are reached only through private endpoints and private DNS.
The Container App's managed identity is granted only the minimum inference RBAC
role; no Azure API key is used in the WriterFlow backend path. Deployment names,
resource hosts, and routing configuration live only in server-side App
Configuration / versioned deploy config (the logical route catalog in
`V2-ARCHITECTURE.md` §10.1), never in a client request or response.

## Consequences

- The client sees only a logical route label (e.g. `standard`, `premium`), never a
  deployment name, resource host, region, or credential.
- If a temporary provider secret is ever unavoidable in a dev environment, it lives
  in Key Vault only and is forbidden in application code, source, or any shipped
  artifact.
- Model/deployment changes are made through server configuration and evals; no Mac
  app update is required to change routing.
- Public network access to Azure OpenAI is disabled and verified disabled in
  staging/prod as a named Phase 5 exit criterion.

## Revisit when

A required provider integration lacks workload identity support — then a
Key Vault-held, server-only secret is the fallback, never a client-visible one.

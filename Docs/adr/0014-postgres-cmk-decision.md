# PostgreSQL CMK decision (Stage 5.1)

**Decision:** Azure Database for PostgreSQL Flexible Server uses **platform-managed keys (PMK)** for dev/staging and **customer-managed keys (CMK)** via Azure Key Vault for production.

## Rationale
- PMK keeps dev/staging cost and operational overhead low while migrations and RLS are proven.
- CMK satisfies enterprise data-at-rest requirements for GA production without blocking early cloud apply.
- Key Vault in `infra/bicep/modules/keyvault.bicep` already provisions the CMK key resource; wire `postgres.bicep` `customerManagedKey` parameter when `environment == 'prod'`.

## Implementation checklist
- [ ] Add `useCmk: bool` parameter to `infra/bicep/modules/postgres.bicep`
- [ ] Pass Key Vault key URI from `keyvault.bicep` output when `useCmk` is true
- [ ] Document key rotation runbook in `Docs/runbooks/postgres-cmk-rotation.md`
- [ ] Verify backup/restore with CMK in staging before prod cutover

**Status:** documented; Bicep wiring is cloud-apply pending alongside first `az deployment`.

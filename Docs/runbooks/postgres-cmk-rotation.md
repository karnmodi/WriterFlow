# PostgreSQL CMK rotation

Production PostgreSQL uses the Key Vault key
`writerflow-postgres-cmk`. Staging uses platform-managed encryption unless a
restore drill explicitly enables CMK.

## Rules

- Never disable, delete, or purge the active key version.
- Keep the previous version enabled until PostgreSQL, backups, replicas, and a
  restore drill have all succeeded with the replacement.
- Rotate through a reviewed Bicep deployment; do not edit the server or vault
  manually without recording the incident/change.
- The PostgreSQL CMK identity receives only **Key Vault Crypto Service
  Encryption User** on this vault.

## Rotation

1. Confirm the database and Key Vault are healthy and take a restorable backup.
2. Create a new enabled version of `writerflow-postgres-cmk` in Key Vault.
3. Update the PostgreSQL `primaryKeyURI` to the new version through Bicep.
4. Wait for the server encryption status to return healthy.
5. Run API readiness, migrations status, authenticated inference, and a
   point-in-time restore drill in staging.
6. Keep the old key version enabled through the documented backup-retention
   window. Disable it only after every retained backup no longer requires it.

## Failure

If PostgreSQL cannot unwrap the data key, restore the prior `primaryKeyURI`
while its version remains enabled. Block API traffic if the database is not
healthy; never create an empty replacement database as recovery.

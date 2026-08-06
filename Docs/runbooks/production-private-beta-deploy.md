# Production private-beta deployment

This runbook deploys the cost-controlled `private-beta-public` profile from
`infra/bicep/main.bicep`. Developer APIM is the public gateway. The Container
Apps API origin is public but requires a Key Vault-backed credential injected
only by APIM. PostgreSQL requires TLS, firewall access, and its least-privilege
role; Key Vault requires RBAC; Azure OpenAI disables reusable keys and accepts
the API's managed identity.
The Standard v2 private-origin profiles are retained for a future scale/SLA gate
but are not part of the private-beta rollout.

## Cost approval gate

Do not deploy a Standard v2 profile during private beta. The beta uses the
existing Developer APIM rather than adding its approximately USD 700/month
fixed charge.

- Azure OpenAI GlobalStandard is pay-per-token; no WriterFlow GPU/model server
  or provisioned-throughput reservation is created.
- PostgreSQL keeps the burstable B1ms beta profile until measured load requires
  an upgrade.
- Container Apps, Log Analytics/Application Insights, ACR, Key Vault,
  private endpoints, bandwidth, and Azure OpenAI: usage-dependent.

Use the Azure Pricing Calculator with UK West and the exact expected traffic
before approval. Budgets and alerts are guardrails, not spending caps.

## Preflight

1. Create separate staging/production Entra confidential-client
   registrations and register the exact auth, pairing, and logout redirects.
2. Create a staging/production resource group and GitHub OIDC deployment
   identity. Do not reuse the dev service principal or tenant registration.
3. Configure protected GitHub environments named `staging` and `production`;
   production requires owner approval. Set environment variables
   `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` for the
   workload-identity federation. Do not create an Azure client secret.
4. Choose the full Git commit SHA as the immutable image tag and push API,
   website, worker, and migration images before applying Container Apps.
5. Create versionless Key Vault secrets for:
   - the least-privilege `writerflow_app` PostgreSQL connection URL;
   - the `writerflow_worker` PostgreSQL connection URL;
   - the dedicated migration-role PostgreSQL connection URL;
   - the Entra confidential-client secret.
   - a random 32-byte-or-longer APIM origin secret.
6. Pass only those Key Vault secret URIs to Bicep. Never pass any secret as
   a plain Container App environment variable.

## Validate without creating resources

```bash
az bicep build --file infra/bicep/main.bicep --stdout >/dev/null
az bicep lint --file infra/bicep/main.bicep

az deployment group what-if \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file infra/bicep/main.bicep \
  --parameters \
    environmentName=dev \
    deploymentProfile=private-beta-public \
    namePrefix="$AZURE_NAME_PREFIX" \
    imageTag="$GITHUB_SHA" \
    privateCoreLocation=ukwest \
    modelLocation=swedencentral \
    azureOpenAIDeploymentName=grammar \
    deployAzureOpenAIModel=false \
    postgresAdministratorPassword="$POSTGRES_ADMINISTRATOR_PASSWORD" \
    databaseUrlSecretUri="$DATABASE_URL_SECRET_URI" \
    migrationDatabaseUrlSecretUri="$MIGRATION_DATABASE_URL_SECRET_URI" \
    workerDatabaseUrlSecretUri="$WORKER_DATABASE_URL_SECRET_URI" \
    entraClientSecretUri="$ENTRA_CLIENT_SECRET_URI" \
    apimOriginSecretUri="$APIM_ORIGIN_SECRET_URI" \
    entraTenantIssuer="$ENTRA_TENANT_ISSUER" \
    entraWebClientId="$ENTRA_WEB_CLIENT_ID"
```

Review every delete/replace operation. A first-resource what-if can report
role assignments as unidentifiable until their managed identities exist; the
deployment must still fail closed if any assignment cannot be created.

## Apply in two passes

The Developer APIM path uses the existing Container Apps TLS edge.

1. Deploy the `private-beta-public` profile without creating Standard v2.
2. Wait for Developer APIM, private DNS, Container Apps, PostgreSQL, Key Vault, and
   Azure OpenAI readiness.
3. Bootstrap `${AZURE_NAME_PREFIX}-migrations` once with the migration image
   and Key Vault secret URI. Every later promotion updates and starts this
   manual Container Apps Job before changing application traffic. The job has
   one replica, no retries, a dedicated identity, and the migration DB role;
   never open PostgreSQL to a hosted runner.
4. Bind `apiwriterflow.aviusolutions.com` to the existing APIM edge and keep
   Cloudflare DNS-only during certificate and SSE verification.

The website's `WRITERFLOW_API_BASE_URL` is deliberately the APIM service's default
`azure-api.net` gateway URL, not the Cloudflare-proxied public hostname. These calls
carry Entra tokens from Next.js server routes and must never receive Cloudflare's
interactive browser challenge. Mac clients continue to use
`apiwriterflow.aviusolutions.com`; both paths still traverse APIM and receive the same
Key Vault-backed origin credential before reaching the API.

## Acceptance probes

- `scripts/cloud/apim-smoke.sh` passes through the custom hostname.
- Browser sign-up/sign-in, `/account`, and device approval pass.
- From the deployed website container, an empty `POST` to the configured
  `/v2/web-session/token` reaches WriterFlow and returns `VALIDATION_FAILED` (400),
  never a Cloudflare challenge (403).
- A paired Mac completes every explicit action through APIM.
- Direct calls to every Container Apps `/v2` origin route return 403 without
  APIM's origin credential. PostgreSQL rejects non-firewalled/TLS-less access,
  Key Vault rejects callers without RBAC, and Azure OpenAI rejects reusable
  keys in favor of the API managed identity.
- No request body or inference content appears in APIM, API, or telemetry.
- Rollback restores the prior Container App revisions and cohort flag without
  replaying an inference operation.
- The metadata-only alert rules and Azure budget notify the operational owner;
  follow `private-beta-operations.md` for incident response and release gates.

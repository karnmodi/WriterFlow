# WriterFlow cloud operations

The preferred production topology remains Standard v2 APIM with outbound VNet
integration to the internal API Container Apps environment. UK South did not
offer that SKU during the first dev deployment, so dev currently uses the
explicit fallback in `infra/bicep/main.bicep`:

`Cloudflare → wfprod-apim-edge → Developer APIM → wfprod-api-public`

Enable it with `useDeveloperApimFallback=true`. Do not use this fallback for a
paid production environment: the API origin and PostgreSQL migration path must
return to private networking first.

## Custom API domain

1. Deploy the edge with `deploy-apim-edge.sh`.
2. In Cloudflare, create a DNS-only CNAME:
   `apiwriterflow` → the edge Container App FQDN.
3. Add the ownership TXT printed by Azure:
   `asuid.apiwriterflow` → the Container App custom-domain verification ID.
4. Run `bind-apiwriterflow.sh`. If Azure prints a second certificate-validation
   TXT record, add exactly that `_dnsauth.apiwriterflow` value in Cloudflare and
   rerun the script.
5. Keep the CNAME DNS-only until the Azure managed certificate is `Succeeded`.
   Then run `apim-smoke.sh`.

Cloudflare must never terminate or cache the SSE response body. The Nginx edge
and APIM inference policy both disable response buffering.

## Reproducible setup and smoke

- `apim-setup.sh` applies named values plus Developer-tier policies.
- `apim-smoke.sh` checks health, JWKS/OIDC, the unauthenticated JWT gate, and
  the custom domain.
- `cloud-e2e.ts` provisions an ephemeral test device and exercises every
  explicit v1 action through APIM. It requires `APIM_GATEWAY` and a migrator
  `DATABASE_URL`; never place either credential in source control.

## Private-network hardening

Before production:

1. Deploy Standard v2 APIM in a supported region and set
   `useDeveloperApimFallback=false`.
2. Remove `wfprod-api-public` and the edge proxy after DNS is moved to the
   production gateway.
3. Disable PostgreSQL public access. Run migrations from a private CI runner,
   Container Apps job, or short-lived jump host in the VNet.
4. Disable Azure OpenAI public network access and resolve its private endpoint
   from the internal API environment.
5. Run the CI migration up/down/up suite and `apim-smoke.sh` after deployment.

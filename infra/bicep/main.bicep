// WriterFlow v2 environment skeleton — V2-ARCHITECTURE.md §2 (mermaid diagram),
// §14.1 (scaling/environment baseline), Stage 5.1 "Azure skeleton".
//
// Status: code complete; cloud apply pending — no Azure subscription is
// connected from this workspace yet. `az deployment group what-if` should be
// run against a real resource group before the first `az deployment group
// create`, and the user must explicitly approve the estimated cost first
// (Standard v2 APIM alone is ~$150+/month) — see the Stage 5.1 phase-file note.
//
// Deliberately NOT deployed by CI: `infra/*` validation in CI is
// `az bicep build` + `what-if` against a throwaway/dev scope only, never an
// automatic `create` (Stage 5.1 "CI and observability" — "production
// deployment is disabled until later phase gates").

targetScope = 'resourceGroup'

@allowed(['dev', 'staging', 'prod'])
param environmentName string

@description('Short, DNS-safe environment/project prefix, e.g. wf-dev.')
param namePrefix string

param location string = resourceGroup().location
@description('Immutable container image tag, normally the full Git commit SHA.')
param imageTag string = 'bootstrap'

@allowed(['dev-public', 'private-beta-public', 'staging-private', 'production-private'])
@description('Explicit topology profile. private-beta-public uses low-cost Developer APIM while keeping data/model resources private; StandardV2 profiles are deferred.')
param deploymentProfile string = environmentName == 'dev'
  ? 'dev-public'
  : environmentName == 'staging'
    ? 'private-beta-public'
    : 'production-private'

@description('UK West is the production core while StandardV2 creation is capacity-blocked in UK South.')
param privateCoreLocation string = 'ukwest'

@description('Azure OpenAI model location; independent from the API/data plane.')
param modelLocation string = 'swedencentral'
@description('Existing logical Azure OpenAI deployment consumed by the beta. No dedicated model compute is provisioned.')
param azureOpenAIDeploymentName string = 'grammar'
@description('Explicit opt-in for creating a new pay-per-token logical deployment. False reuses the existing deployment.')
param deployAzureOpenAIModel bool = false

@description('Second deployment pass only: bind apiwriterflow.aviusolutions.com after APIM exists and DNS validation is ready.')
param configureApimCustomDomain bool = false
@description('Second deployment pass only: bind writerflow.aviusolutions.com after website DNS validation is ready.')
param configureWebsiteCustomDomain bool = false

@description('Versionless Key Vault secret URI containing the PostgreSQL app-role connection string.')
param databaseUrlSecretUri string = ''
@description('Versionless Key Vault secret URI containing the least-privilege migration-role connection string.')
param migrationDatabaseUrlSecretUri string = ''
@description('Versionless Key Vault secret URI for the metadata-only writerflow_worker connection string.')
param workerDatabaseUrlSecretUri string = ''

@description('Versionless Key Vault secret URI containing the Entra confidential-client secret.')
param entraClientSecretUri string = ''
@description('Versionless Key Vault secret URI for APIM-to-origin authentication on the low-cost public API edge.')
param apimOriginSecretUri string = ''

param entraTenantIssuer string = ''
param entraJwksUri string = ''
param entraWebClientId string = ''
param jwtPreviousSigningKeyNames string = ''

var isDevPublic = deploymentProfile == 'dev-public'
var useDeveloperApim = isDevPublic || deploymentProfile == 'private-beta-public'
var configureCloudRuntime = !isDevPublic
var isPrivateProfile = deploymentProfile == 'staging-private' || deploymentProfile == 'production-private'
var disablePublicNetworkAccess = isPrivateProfile
var coreLocation = useDeveloperApim ? location : privateCoreLocation
var deployWorker = configureCloudRuntime && !empty(workerDatabaseUrlSecretUri)
var deployMigrationJob = configureCloudRuntime && !empty(migrationDatabaseUrlSecretUri)

@secure()
@description('PostgreSQL migrator admin password — pass at deploy time; never commit.')
param postgresAdministratorPassword string

param apimPublisherEmail string = 'engineering@writerflow.aviusolutions.com'

param budgetNotificationEmail string = 'engineering@writerflow.aviusolutions.com'

module network 'modules/network.bicep' = {
  name: '${namePrefix}-network'
  params: {
    namePrefix: namePrefix
    location: coreLocation
  }
}

module logAnalytics 'modules/monitoring.bicep' = {
  name: '${namePrefix}-monitoring'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    notificationEmail: budgetNotificationEmail
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: '${namePrefix}-keyvault'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    subnetId: network.outputs.privateEndpointsSubnetId
    vnetId: network.outputs.vnetId
    disablePublicNetworkAccess: disablePublicNetworkAccess
  }
}

module postgres 'modules/postgres.bicep' = {
  name: '${namePrefix}-postgres'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    subnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresPrivateDnsZoneId
    disablePublicNetworkAccess: disablePublicNetworkAccess
    environmentName: environmentName
    administratorPassword: postgresAdministratorPassword
    useCmk: deploymentProfile == 'production-private'
    keyVaultName: keyVault.outputs.keyVaultName
    cmkKeyUri: keyVault.outputs.postgresCmkKeyUri
  }
}

module containerRegistry 'modules/container-registry.bicep' = {
  name: '${namePrefix}-acr'
  params: {
    namePrefix: namePrefix
    location: coreLocation
  }
}

module containerAppsEnv 'modules/container-apps-env.bicep' = {
  name: '${namePrefix}-cae'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    infrastructureSubnetId: network.outputs.containerAppsSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    internal: true
  }
}

// Separate, genuinely public environment for website/ — see
// container-app-website.bicep for why this can't share the API's
// internal-only environment.
module websiteContainerAppsEnv 'modules/container-apps-env.bicep' = {
  name: '${namePrefix}-website-cae'
  params: {
    namePrefix: '${namePrefix}-web'
    location: coreLocation
    infrastructureSubnetId: network.outputs.websiteContainerAppsSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    internal: false
  }
}

module appConfiguration 'modules/app-configuration.bicep' = {
  name: '${namePrefix}-appconfig'
  params: {
    namePrefix: namePrefix
    location: coreLocation
  }
}

module deletionRegistry 'modules/deletion-registry.bicep' = {
  name: '${namePrefix}-deletion-registry'
  params: {
    namePrefix: namePrefix
    location: coreLocation
  }
}

// Resolve *.${apiCaeDefaultDomain} to the internal CAE static IP inside the
// VNet — required for Standard v2 APIM outbound. On private-beta (Developer APIM)
// the public API already lives on the website CAE, and Azure often auto-links the
// internal CAE default-domain zone to the VNet — recreating that link Conflict-fails.
module apiCaeDns 'modules/cae-dns.bicep' = if (!useDeveloperApim) {
  name: '${namePrefix}-api-cae-dns'
  params: {
    defaultDomain: containerAppsEnv.outputs.defaultDomain
    staticIp: containerAppsEnv.outputs.staticIp
    vnetId: network.outputs.vnetId
    linkName: '${namePrefix}-api-cae-dns-link'
    createVnetLink: true
  }
}

module azureOpenAI 'modules/azure-openai.bicep' = if (configureCloudRuntime) {
  name: '${namePrefix}-azure-openai'
  params: {
    namePrefix: namePrefix
    location: modelLocation
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    vnetId: network.outputs.vnetId
    disablePublicNetworkAccess: disablePublicNetworkAccess
    deployInitialModel: deployAzureOpenAIModel
    deploymentName: azureOpenAIDeploymentName
  }
}

module apiApp 'modules/container-app-api.bicep' = if (!useDeveloperApim) {
  name: '${namePrefix}-api-app'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    containerAppsEnvironmentId: containerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultUri: keyVault.outputs.vaultUri
    imageTag: imageTag
    environmentVariables: [
      {
        name: 'NODE_ENV'
        value: 'production'
      }
      {
        name: 'WEBSITE_BASE_URL'
        value: 'https://writerflow.aviusolutions.com'
      }
      {
        name: 'ENTRA_TENANT_ISSUER'
        value: entraTenantIssuer
      }
      {
        name: 'ENTRA_JWKS_URI'
        value: entraJwksUri
      }
      {
        name: 'ENTRA_WEB_CLIENT_ID'
        value: entraWebClientId
      }
      {
        name: 'JWT_SIGNING_KEY_VAULT_URL'
        value: keyVault.outputs.vaultUri
      }
      {
        name: 'JWT_SIGNING_KEY_NAME'
        value: keyVault.outputs.jwtSigningKeyName
      }
      {
        name: 'JWT_SIGNING_PREVIOUS_KEY_NAMES'
        value: jwtPreviousSigningKeyNames
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: azureOpenAI!.outputs.endpoint
      }
      {
        name: 'AZURE_OPENAI_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_GRAMMAR_FAST_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_REWRITE_STANDARD_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_PROMPT_ENHANCER_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_API_VERSION'
        value: '2024-12-01-preview'
      }
      {
        name: 'AZURE_OPENAI_REASONING_EFFORT'
        value: 'minimal'
      }
      {
        name: 'AZURE_OPENAI_MAX_COMPLETION_TOKENS'
        value: '1024'
      }
      {
        name: 'WRITERFLOW_COHORT_CLOUD_INFERENCE'
        value: 'true'
      }
      {
        name: 'WRITERFLOW_COHORT_BYO_FALLBACK'
        value: 'false'
      }
    ]
    secretEnvironmentVariables: concat(empty(databaseUrlSecretUri) ? [] : [
      {
        name: 'DATABASE_URL'
        secretRef: 'database-url'
        keyVaultUrl: databaseUrlSecretUri
      }
    ], empty(apimOriginSecretUri) ? [] : [
      {
        name: 'APIM_ORIGIN_SECRET'
        secretRef: 'apim-origin-secret'
        keyVaultUrl: apimOriginSecretUri
      }
    ])
  }
}

module publicApiApp 'modules/container-app-api.bicep' = if (useDeveloperApim) {
  name: '${namePrefix}-api-public-app'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    containerAppsEnvironmentId: websiteContainerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultUri: keyVault.outputs.vaultUri
    appSuffix: 'api-public'
    identitySuffix: 'api-public-identity'
    imageTag: imageTag
    environmentVariables: isDevPublic ? [] : [
      {
        name: 'NODE_ENV'
        value: 'production'
      }
      {
        name: 'WEBSITE_BASE_URL'
        value: 'https://writerflow.aviusolutions.com'
      }
      {
        name: 'ENTRA_TENANT_ISSUER'
        value: entraTenantIssuer
      }
      {
        name: 'ENTRA_JWKS_URI'
        value: entraJwksUri
      }
      {
        name: 'ENTRA_WEB_CLIENT_ID'
        value: entraWebClientId
      }
      {
        name: 'JWT_SIGNING_KEY_VAULT_URL'
        value: keyVault.outputs.vaultUri
      }
      {
        name: 'JWT_SIGNING_KEY_NAME'
        value: keyVault.outputs.jwtSigningKeyName
      }
      {
        name: 'JWT_SIGNING_PREVIOUS_KEY_NAMES'
        value: jwtPreviousSigningKeyNames
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: azureOpenAI!.outputs.endpoint
      }
      {
        name: 'AZURE_OPENAI_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_GRAMMAR_FAST_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_REWRITE_STANDARD_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_PROMPT_ENHANCER_DEPLOYMENT'
        value: azureOpenAI!.outputs.deploymentName
      }
      {
        name: 'AZURE_OPENAI_API_VERSION'
        value: '2024-12-01-preview'
      }
      {
        name: 'AZURE_OPENAI_REASONING_EFFORT'
        value: 'minimal'
      }
      {
        name: 'AZURE_OPENAI_MAX_COMPLETION_TOKENS'
        value: '1024'
      }
      {
        name: 'WRITERFLOW_COHORT_CLOUD_INFERENCE'
        value: 'true'
      }
      {
        name: 'WRITERFLOW_COHORT_BYO_FALLBACK'
        value: 'false'
      }
    ]
    secretEnvironmentVariables: isDevPublic ? [] : concat(empty(databaseUrlSecretUri) ? [] : [
      {
        name: 'DATABASE_URL'
        secretRef: 'database-url'
        keyVaultUrl: databaseUrlSecretUri
      }
    ], empty(apimOriginSecretUri) ? [] : [
      {
        name: 'APIM_ORIGIN_SECRET'
        secretRef: 'apim-origin-secret'
        keyVaultUrl: apimOriginSecretUri
      }
    ])
  }
}

module workerApp 'modules/container-app-worker.bicep' = if (deployWorker) {
  name: '${namePrefix}-worker-app'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    containerAppsEnvironmentId: containerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    databaseUrlSecretUri: workerDatabaseUrlSecretUri
    imageTag: imageTag
  }
}

module migrationJob 'modules/container-app-migrations.bicep' = if (deployMigrationJob) {
  name: '${namePrefix}-migration-job'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    // Private-beta API + website share the public CAE; the prod job already lives
    // there. Pointing at the internal CAE fails with ContainerAppsJobEnvironmentMismatch.
    containerAppsEnvironmentId: useDeveloperApim
      ? websiteContainerAppsEnv.outputs.environmentId
      : containerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    databaseUrlSecretUri: migrationDatabaseUrlSecretUri
    imageTag: imageTag
  }
}

module websiteApp 'modules/container-app-website.bicep' = {
  name: '${namePrefix}-website-app'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    containerAppsEnvironmentId: websiteContainerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultUri: keyVault.outputs.vaultUri
    imageTag: imageTag
    configureCustomDomain: configureWebsiteCustomDomain
    environmentVariables: isDevPublic ? [] : [
      {
        name: 'NODE_ENV'
        value: 'production'
      }
      {
        name: 'SITE_ORIGIN'
        value: 'https://writerflow.aviusolutions.com'
      }
      {
        name: 'NEXT_PUBLIC_SITE_ORIGIN'
        value: 'https://writerflow.aviusolutions.com'
      }
      {
        name: 'ENTRA_TENANT_ISSUER'
        value: entraTenantIssuer
      }
      {
        name: 'ENTRA_WEB_CLIENT_ID'
        value: entraWebClientId
      }
      {
        name: 'PAIR_REDIRECT_URI'
        value: 'https://writerflow.aviusolutions.com/pair/callback'
      }
      {
        name: 'AUTH_REDIRECT_URI'
        value: 'https://writerflow.aviusolutions.com/auth/callback'
      }
      {
        name: 'WRITERFLOW_API_BASE_URL'
        // Server-to-server auth exchanges must bypass the Cloudflare-proxied
        // public hostname: Cloudflare presents a browser challenge to the
        // Container Apps egress IP. This still traverses APIM, which injects
        // the Key Vault-backed origin credential before reaching the API.
        value: '${apim.outputs.gatewayUrl}/v2'
      }
      {
        name: 'NEXT_PUBLIC_RELEASE_STATUS'
        value: 'private-beta'
      }
    ]
    secretEnvironmentVariables: empty(entraClientSecretUri) ? [] : [
      {
        name: 'ENTRA_WEB_CLIENT_SECRET'
        secretRef: 'entra-web-client-secret'
        keyVaultUrl: entraClientSecretUri
      }
    ]
  }
}

module apim 'modules/apim.bicep' = {
  name: '${namePrefix}-apim'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    outboundSubnetId: network.outputs.apimSubnetId
    apiAppFqdn: useDeveloperApim ? publicApiApp!.outputs.fqdn : apiApp!.outputs.fqdn
    publisherEmail: apimPublisherEmail
    developerFallback: useDeveloperApim
    originSharedSecretUri: apimOriginSecretUri
    configureCustomDomain: configureApimCustomDomain
  }
}

module apimEdge 'modules/container-app-apim-edge.bicep' = if (useDeveloperApim) {
  name: '${namePrefix}-apim-edge'
  params: {
    namePrefix: namePrefix
    location: coreLocation
    containerAppsEnvironmentId: websiteContainerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    apimGatewayHost: apim.outputs.gatewayHost
    imageTag: imageTag
  }
}

module workloadRbac 'modules/workload-rbac.bicep' = {
  name: '${namePrefix}-workload-rbac'
  params: {
    containerRegistryName: containerRegistry.outputs.registryName
    keyVaultName: keyVault.outputs.keyVaultName
    azureOpenAIAccountName: isDevPublic ? '' : azureOpenAI!.outputs.accountName
    apiPrincipalId: useDeveloperApim
      ? publicApiApp!.outputs.identityPrincipalId
      : apiApp!.outputs.identityPrincipalId
    websitePrincipalId: websiteApp.outputs.identityPrincipalId
    workerPrincipalId: deployWorker ? workerApp!.outputs.identityPrincipalId : ''
    includeWorker: deployWorker
    migrationPrincipalId: deployMigrationJob ? migrationJob!.outputs.identityPrincipalId : ''
    includeMigrationJob: deployMigrationJob
    apimPrincipalId: apim.outputs.identityPrincipalId
    includeApimKeyVault: !empty(apimOriginSecretUri)
    includeAzureOpenAI: configureCloudRuntime
  }
}

module budget 'modules/budget.bicep' = {
  name: '${namePrefix}-budget'
  params: {
    namePrefix: namePrefix
    environmentName: environmentName
    notificationEmail: budgetNotificationEmail
  }
}

output apiAppFqdn string = useDeveloperApim ? publicApiApp!.outputs.fqdn : apiApp!.outputs.fqdn
output websiteAppFqdn string = websiteApp.outputs.fqdn
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimEdgeFqdn string = useDeveloperApim ? apimEdge!.outputs.fqdn : ''
output keyVaultUri string = keyVault.outputs.vaultUri
output postgresFqdn string = postgres.outputs.fqdn
output appConfigEndpoint string = appConfiguration.outputs.endpoint
output deletionRegistryStorageAccountName string = deletionRegistry.outputs.storageAccountName
output deploymentProfile string = deploymentProfile
output coreLocation string = coreLocation
output azureOpenAIEndpoint string = configureCloudRuntime ? azureOpenAI!.outputs.endpoint : ''
output migrationJobName string = deployMigrationJob ? migrationJob!.outputs.jobName : ''

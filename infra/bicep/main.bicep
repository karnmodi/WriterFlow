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

@description('Whether Container Apps/Postgres/Key Vault/AOAI get public network access disabled. Always true outside dev per the phase-wide non-negotiables.')
param disablePublicNetworkAccess bool = environmentName != 'dev'

@secure()
@description('PostgreSQL migrator admin password — pass at deploy time; never commit.')
param postgresAdministratorPassword string

param apimPublisherEmail string = 'engineering@writerflow.aviusolutions.com'

param budgetNotificationEmail string = 'engineering@writerflow.aviusolutions.com'

module network 'modules/network.bicep' = {
  name: '${namePrefix}-network'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

module logAnalytics 'modules/monitoring.bicep' = {
  name: '${namePrefix}-monitoring'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: '${namePrefix}-keyvault'
  params: {
    namePrefix: namePrefix
    location: location
    subnetId: network.outputs.privateEndpointsSubnetId
    disablePublicNetworkAccess: disablePublicNetworkAccess
  }
}

module postgres 'modules/postgres.bicep' = {
  name: '${namePrefix}-postgres'
  params: {
    namePrefix: namePrefix
    location: location
    subnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresPrivateDnsZoneId
    disablePublicNetworkAccess: disablePublicNetworkAccess
    environmentName: environmentName
    administratorPassword: postgresAdministratorPassword
  }
}

module containerRegistry 'modules/container-registry.bicep' = {
  name: '${namePrefix}-acr'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

module containerAppsEnv 'modules/container-apps-env.bicep' = {
  name: '${namePrefix}-cae'
  params: {
    namePrefix: namePrefix
    location: location
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
    location: location
    infrastructureSubnetId: network.outputs.websiteContainerAppsSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    internal: false
  }
}

module appConfiguration 'modules/app-configuration.bicep' = {
  name: '${namePrefix}-appconfig'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

module deletionRegistry 'modules/deletion-registry.bicep' = {
  name: '${namePrefix}-deletion-registry'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

// Resolve *.${apiCaeDefaultDomain} to the internal CAE static IP inside the
// VNet — required for APIM outbound and website→API server-to-server calls.
module apiCaeDns 'modules/cae-dns.bicep' = {
  name: '${namePrefix}-api-cae-dns'
  params: {
    defaultDomain: containerAppsEnv.outputs.defaultDomain
    staticIp: containerAppsEnv.outputs.staticIp
    vnetId: network.outputs.vnetId
    linkName: '${namePrefix}-api-cae-dns-link'
  }
}

module apiApp 'modules/container-app-api.bicep' = {
  name: '${namePrefix}-api-app'
  params: {
    namePrefix: namePrefix
    location: location
    containerAppsEnvironmentId: containerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultUri: keyVault.outputs.vaultUri
  }
}

module websiteApp 'modules/container-app-website.bicep' = {
  name: '${namePrefix}-website-app'
  params: {
    namePrefix: namePrefix
    location: location
    containerAppsEnvironmentId: websiteContainerAppsEnv.outputs.environmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultUri: keyVault.outputs.vaultUri
  }
}

module apim 'modules/apim.bicep' = {
  name: '${namePrefix}-apim'
  params: {
    namePrefix: namePrefix
    location: location
    outboundSubnetId: network.outputs.apimSubnetId
    apiAppFqdn: apiApp.outputs.fqdn
    publisherEmail: apimPublisherEmail
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

output apiAppFqdn string = apiApp.outputs.fqdn
output websiteAppFqdn string = websiteApp.outputs.fqdn
output apimGatewayUrl string = apim.outputs.gatewayUrl
output keyVaultUri string = keyVault.outputs.vaultUri
output postgresFqdn string = postgres.outputs.fqdn
output appConfigEndpoint string = appConfiguration.outputs.endpoint
output deletionRegistryStorageAccountName string = deletionRegistry.outputs.storageAccountName

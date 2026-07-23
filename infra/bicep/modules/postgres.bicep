// Azure Database for PostgreSQL Flexible Server, private access only.
// Status: code complete; cloud apply pending. Stage 5.1 "Decide and provision
// the production CMK mode before production server creation" is an explicit
// open decision — this module defaults to platform-managed keys and must be
// revisited (Azure documents the mode cannot change after creation) before
// any real prod server is created from it.

param namePrefix string
param location string
param subnetId string
param privateDnsZoneId string
param disablePublicNetworkAccess bool
@allowed(['dev', 'staging', 'prod'])
param environmentName string
param useCmk bool = environmentName == 'prod'
param keyVaultName string = ''
param cmkKeyUri string = ''

// Dev-only placeholder default. Staging/prod callers must pass this from a
// Key Vault reference in the deployment pipeline, never rely on the default —
// a newGuid() default regenerates on every deployment, which is fine for a
// throwaway dev server but would rotate the admin password on every redeploy
// of a real one.
@secure()
param administratorPassword string = newGuid()

var skuByEnvironment = {
  dev: { name: 'Standard_B1ms', tier: 'Burstable' }
  staging: { name: 'Standard_D2ds_v5', tier: 'GeneralPurpose' }
  prod: { name: 'Standard_D4ds_v5', tier: 'GeneralPurpose' }
}
var storageMbByEnvironment = {
  dev: 32768
  staging: 65536
  prod: 131072
}
var backupRetentionDaysByEnvironment = {
  dev: 7
  staging: 14
  prod: 35
}

resource cmkIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (useCmk) {
  name: '${namePrefix}-pg-cmk-identity'
  location: location
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = if (useCmk) {
  name: keyVaultName
}

var keyVaultCryptoServiceEncryptionUserRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'e147488a-f6f5-4113-8e2d-b22465e65bf6'
)

resource cmkRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useCmk) {
  name: guid(keyVault!.id, cmkIdentity!.id, keyVaultCryptoServiceEncryptionUserRole)
  scope: keyVault!
  properties: {
    principalId: cmkIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultCryptoServiceEncryptionUserRole
  }
}

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: '${namePrefix}-pg'
  location: location
  sku: skuByEnvironment[environmentName]
  identity: useCmk ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cmkIdentity!.id}': {}
    }
  } : {
    type: 'None'
  }
  properties: {
    version: '17'
    administratorLogin: 'writerflow_migrator'
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageMbByEnvironment[environmentName] / 1024
    }
    backup: {
      backupRetentionDays: backupRetentionDaysByEnvironment[environmentName]
      geoRedundantBackup: environmentName == 'prod' ? 'Enabled' : 'Disabled'
    }
    network: disablePublicNetworkAccess
      ? {
          delegatedSubnetResourceId: subnetId
          privateDnsZoneArmResourceId: privateDnsZoneId
          publicNetworkAccess: 'Disabled'
        }
      : {
          publicNetworkAccess: 'Enabled'
        }
    highAvailability: {
      mode: environmentName == 'prod' ? 'ZoneRedundant' : 'Disabled'
    }
    dataEncryption: useCmk ? {
      type: 'AzureKeyVault'
      primaryKeyURI: cmkKeyUri
      primaryUserAssignedIdentityId: cmkIdentity!.id
    } : {
      type: 'SystemManaged'
    }
  }
  dependsOn: useCmk ? [cmkRole] : []
}

resource enforceTls 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: server
  name: 'require_secure_transport'
  properties: {
    value: 'on'
    source: 'user-override'
  }
}

output fqdn string = server.properties.fullyQualifiedDomainName
output serverId string = server.id

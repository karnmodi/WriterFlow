// Status: code complete; cloud apply pending. Signs WriterFlow device tokens
// (ADR-0012) and wraps envelope-encryption DEKs (V2-ARCHITECTURE.md §7.2).

param namePrefix string
param location string
param subnetId string
param disablePublicNetworkAccess bool

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: '${namePrefix}-kv'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: disablePublicNetworkAccess ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (disablePublicNetworkAccess) {
  name: '${namePrefix}-kv-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-kv-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

output vaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id

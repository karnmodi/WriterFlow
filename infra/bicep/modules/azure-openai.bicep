// Private Azure OpenAI account and optional initial deployment. The API uses
// managed identity/RBAC; no provider key is exposed to Container Apps or clients.

param namePrefix string
param location string
param privateEndpointsSubnetId string
param vnetId string
param disablePublicNetworkAccess bool = true
param deployInitialModel bool = true
param deploymentName string = 'grammar-fast'
param modelName string = 'gpt-5-mini'
param modelVersion string = '2025-08-07'
param deploymentSkuName string = 'GlobalStandard'
param deploymentCapacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${namePrefix}-openai'
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: '${namePrefix}-openai'
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: disablePublicNetworkAccess ? 'Deny' : 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    disableLocalAuth: true
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployInitialModel) {
  parent: account
  name: deploymentName
  sku: {
    name: deploymentSkuName
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (disablePublicNetworkAccess) {
  name: 'privatelink.openai.azure.com'
  location: 'global'
}

resource privateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (disablePublicNetworkAccess) {
  parent: privateDnsZone
  name: '${namePrefix}-openai-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (disablePublicNetworkAccess) {
  name: '${namePrefix}-openai-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-openai-connection'
        properties: {
          privateLinkServiceId: account.id
          groupIds: ['account']
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (disablePublicNetworkAccess) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'openai'
        properties: {
          privateDnsZoneId: privateDnsZone!.id
        }
      }
    ]
  }
}

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.endpoint
output deploymentName string = deploymentName

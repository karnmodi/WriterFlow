// Status: code complete; cloud apply pending.

param namePrefix string
param location string
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: replace('${namePrefix}acr', '-', '')
  location: location
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false
  }
}

output loginServer string = registry.properties.loginServer
output registryId string = registry.id

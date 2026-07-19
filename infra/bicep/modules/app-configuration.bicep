// Non-secret config store for logical route → target mapping (Stage 5.5) and
// other versioned deploy config. Never holds credentials — those stay in Key
// Vault. Status: code complete; cloud apply pending.

param namePrefix string
param location string

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2024-06-01' = {
  name: '${namePrefix}-appconfig'
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    disableLocalAuth: true
  }
}

output endpoint string = appConfig.properties.endpoint
output appConfigId string = appConfig.id

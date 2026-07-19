// Separate least-privilege Azure Storage deletion-tombstone registry,
// deliberately outside PostgreSQL's restore domain — V2-ARCHITECTURE.md §7.2
// "Keep deletion tombstones outside the restored database path... in a
// separate least-privilege Azure Storage deletion registry that is not
// rolled back with PostgreSQL." Docs/v2-data-retention-policy.md's
// account-deletion sequencing step 3 writes here before any row deletion.
// Status: code complete; cloud apply pending.

param namePrefix string
param location string

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: replace('${namePrefix}delreg', '-', '')
  location: location
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 90
    }
    isVersioningEnabled: true
  }
}

resource tombstoneContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'deletion-tombstones'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
